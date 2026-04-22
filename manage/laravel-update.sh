#!/bin/bash
###############################################################################
#  manage/laravel-update.sh — Update an installed Laravel app
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage laravel-update <domain>
#
#  Runs `composer update` in the site root to pull the latest compatible
#  package versions, re-owns the tree to the nginx user (composer writes as
#  root), runs `php artisan optimize:clear` to flush stale cache/view/route/
#  config compilations, and offers to run `php artisan migrate --force` for
#  any newly-introduced migrations.
#
#  Refuses to run on non-Laravel domains (WordPress/raw). Preserves .env.
###############################################################################

cmd_laravel_update() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage laravel-update <domain>"

    _domain_exists "$domain" \
        || err "No vhost found for '${domain}'. Run 'lemp-manage add-domain ${domain}' first."

    local site_root="${WEB_ROOT_BASE}/${domain}"
    [[ -d "$site_root" ]] || err "Web root not found: ${site_root}"

    # --- App-type gate -------------------------------------------------------
    local kind
    kind=$(_app_detect "$domain")
    [[ "$kind" == "laravel" ]] \
        || err "Not a Laravel app at ${site_root} (detected: ${kind}). Install with 'lemp-manage laravel-install ${domain}' first."

    # --- Pre-flight ----------------------------------------------------------
    command_exists composer \
        || err "composer not found. Re-run the installer or install composer manually."
    command_exists php \
        || err "php not found. Re-run the installer."

    _detect_nginx_user

    section "Updating Laravel: ${domain}"

    # --- Step 1: composer update --------------------------------------------
    info "Running composer update..."
    ( cd "$site_root" && COMPOSER_ALLOW_SUPERUSER=1 composer update \
          --no-interaction --no-progress ) \
        || err "composer update failed. Run 'cd ${site_root} && composer diagnose' to investigate."

    # --- Step 2: re-own composer's root-created files -----------------------
    # composer runs as root; new vendor files land as root-owned. FPM (running
    # as NGINX_USER) then can't read them on next request. Mirror cmd_laravel_install.
    info "Restoring ownership to ${NGINX_USER}..."
    chown -R "${NGINX_USER}:${NGINX_USER}" "$site_root"
    chmod -R 775 "${site_root}/storage" "${site_root}/bootstrap/cache"

    # --- Step 3: clear compiled caches --------------------------------------
    # Must run AFTER composer update — new package versions may register new
    # cache keys; stale optimize cache breaks the first post-update request.
    info "Clearing compiled caches (cache, views, routes, config)..."
    ( cd "$site_root" && php artisan optimize:clear ) \
        || err "php artisan optimize:clear failed. Run manually in ${site_root}."

    # --- Step 4: optional migrate -------------------------------------------
    echo ""
    if confirm "Run 'php artisan migrate --force' to apply any new migrations?" "Y"; then
        info "Running migrations..."
        ( cd "$site_root" && php artisan migrate --force ) \
            || warn "Migrations failed — re-run manually: cd ${site_root} && php artisan migrate"
    else
        info "Skipping migrations. Run later with: cd ${site_root} && php artisan migrate"
    fi

    log "Laravel updated on ${domain}."
}
