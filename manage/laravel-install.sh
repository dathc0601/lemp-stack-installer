#!/bin/bash
###############################################################################
#  manage/laravel-install.sh — Install Laravel on a configured domain
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage laravel-install <domain>
#
#  Runs `composer create-project laravel/laravel` into a temp dir, swaps the
#  contents into the domain's web root, writes .env with the domain's DB
#  credentials, generates APP_KEY, sets writable perms on storage/ +
#  bootstrap/cache/, rewrites the vhost's `root` directive to point at
#  <site_root>/public, tests + reloads nginx, and offers to run migrations.
#
#  Composer picks the highest Laravel compatible with the active PHP version
#  (Laravel 11 needs 8.2+; 10 works on 8.1), so we intentionally do not pin.
###############################################################################

cmd_laravel_install() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage laravel-install <domain>"

    _domain_exists "$domain" \
        || err "No vhost found for '${domain}'. Run 'lemp-manage add-domain ${domain}' first."

    local site_root="${WEB_ROOT_BASE}/${domain}"
    [[ -d "$site_root" ]] || err "Web root not found: ${site_root}"

    # --- Refuse to clobber an existing app ----------------------------------
    local kind
    kind=$(_app_detect "$domain")
    case "$kind" in
        laravel)
            err "Laravel is already installed at ${site_root}/artisan."
            ;;
        wordpress)
            err "WordPress is already installed on ${domain}. Remove the domain and re-add it to start fresh."
            ;;
        unknown)
            warn "Directory ${site_root} is not empty (non-welcome files detected)."
            confirm "Remove all files and install Laravel?" "N" \
                || { info "Aborted."; return 0; }
            ;;
        missing)
            err "Web root ${site_root} does not exist."
            ;;
        empty)
            : # proceed silently — only the stock welcome file is present
            ;;
    esac

    # --- Pre-flight checks --------------------------------------------------
    command_exists composer \
        || err "composer not found. Re-run the installer or install composer manually."
    command_exists php \
        || err "php not found. Re-run the installer."

    _detect_nginx_user

    # --- Read this domain's DB credentials (mirrors cmd_wp_install) --------
    local db_name db_user db_pass
    db_name=$(_domain_db_name "$domain")
    db_user="${db_name}_user"
    db_pass=$(_read_domain_db_pass "$domain")
    [[ -n "$db_pass" ]] \
        || err "Cannot find DB password for '${domain}' in ${CREDENTIALS_FILE}. Was the domain added via lemp-manage or the installer?"

    section "Installing Laravel: ${domain}"

    # --- Step 1: composer create-project into a temp dir --------------------
    # Target must be empty for composer; installing to tmpdir avoids clashes
    # with the stock index.html or any user files we're about to clear.
    local tmpdir
    tmpdir=$(mktemp -d)
    # RETURN trap keeps the tmpdir cleanup local to this function even on err.
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" RETURN

    info "Running composer create-project laravel/laravel..."
    COMPOSER_ALLOW_SUPERUSER=1 composer create-project --prefer-dist \
        laravel/laravel "$tmpdir" \
        --no-interaction --no-progress --quiet \
        || err "composer create-project failed. Run 'COMPOSER_ALLOW_SUPERUSER=1 composer create-project laravel/laravel /tmp/laravel-test' manually to diagnose."

    [[ -f "${tmpdir}/artisan" ]] \
        || err "composer finished but ${tmpdir}/artisan is missing — Laravel skeleton incomplete."

    # --- Step 2: clear site_root and move Laravel contents in --------------
    info "Swapping Laravel into ${site_root}..."
    # :? guards against catastrophic expansion if site_root somehow went empty
    rm -rf "${site_root:?}"/* 2>/dev/null || true
    rm -rf "${site_root:?}"/.[!.]* 2>/dev/null || true

    # dotglob so .env.example / .gitignore / .editorconfig come along too
    shopt -s dotglob
    mv "${tmpdir}"/* "${site_root}/"
    shopt -u dotglob

    # --- Step 3: write .env with this domain's DB + APP_URL -----------------
    info "Configuring .env..."
    local env_file="${site_root}/.env"
    cp "${site_root}/.env.example" "$env_file" \
        || err ".env.example missing in Laravel skeleton."

    sed -i "s|^APP_URL=.*|APP_URL=https://${domain}|"  "$env_file"
    sed -i "s|^APP_NAME=.*|APP_NAME=\"${domain}\"|"   "$env_file"
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${db_name}|" "$env_file"
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${db_user}|" "$env_file"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_pass}|" "$env_file"
    chmod 640 "$env_file"

    # --- Step 4: generate APP_KEY ------------------------------------------
    info "Generating APP_KEY..."
    ( cd "$site_root" && php artisan key:generate --force --quiet ) \
        || err "php artisan key:generate failed."

    # --- Step 5: ownership + writable paths --------------------------------
    # Laravel needs storage/ and bootstrap/cache/ writable by the web user.
    # chown the whole tree to nginx user so composer's Git-created files
    # don't leave root-owned artifacts in the runtime path.
    info "Setting ownership to ${NGINX_USER}..."
    chown -R "${NGINX_USER}:${NGINX_USER}" "$site_root"
    chmod -R 775 "${site_root}/storage" "${site_root}/bootstrap/cache"

    # --- Step 6: rewrite vhost root to <site_root>/public ------------------
    local vhost="${NGINX_CONF_DIR}/${domain}.conf"
    [[ -f "$vhost" ]] || err "vhost file vanished: ${vhost}"

    info "Rewriting vhost root: /var/www/${domain} → /var/www/${domain}/public..."
    # Only rewrite the literal "root /var/www/${domain};" line — leave any
    # other path references (try_files, disallow blocks) untouched.
    sed -i "s|root /var/www/${domain};|root /var/www/${domain}/public;|g" "$vhost"

    # --- Step 7: nginx -t gate + reload ------------------------------------
    if ! nginx -t 2>&1 | tail -5; then
        err "nginx -t failed after vhost rewrite. Inspect ${vhost} manually (expected: 'root /var/www/${domain}/public;') or re-run 'lemp-manage remove-domain ${domain} && lemp-manage add-domain ${domain}' to reset."
    fi
    systemctl reload nginx \
        || err "systemctl reload nginx failed. Check 'journalctl -u nginx'."

    # --- Step 8: optional php artisan migrate ------------------------------
    echo ""
    if confirm "Run 'php artisan migrate' now to initialize the database schema?" "Y"; then
        info "Running migrations..."
        ( cd "$site_root" && php artisan migrate --force ) \
            || warn "Migrations failed — re-run manually: cd ${site_root} && php artisan migrate"
    else
        info "Skipping migrations. Run later with: cd ${site_root} && php artisan migrate"
    fi

    # --- Success ------------------------------------------------------------
    log "Laravel installed on ${domain}: vhost root → /public, nginx reloaded."
    echo ""
    info "Application URL:"
    echo "  https://${domain}/"
    echo ""
    info "Database credentials (already wired in .env):"
    echo "  DB name : ${db_name}"
    echo "  DB user : ${db_user}"
    echo "  DB pass : (see ${CREDENTIALS_FILE})"
    echo ""
    info "Next steps:"
    echo "  cd ${site_root}"
    echo "  php artisan migrate        # if you skipped it above"
    echo "  php artisan storage:link   # if you plan to serve uploads via public/storage"
    echo ""
}
