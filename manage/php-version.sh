#!/bin/bash
###############################################################################
#  manage/php-version.sh — Switch the active PHP version (global)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage php-version [version]
#    version: major.minor (e.g. 8.3). If omitted, prompts with a picker.
#
#  Supports only ondrej/php-packaged versions (8.1–8.4) on Ubuntu 22.04/24.04.
#  Installs the target if missing, copies forward the user's current ini +
#  pool tuning, rewrites vhost socket paths, reloads nginx, then stops the
#  old FPM. Old packages are NOT removed — rollback is `php-version <old>`.
###############################################################################

# Versions we're willing to offer. Lowest → highest; ondrej/php supports these
# on Ubuntu 22.04+. Keep 7.x off — EOL and gets noisy dependency issues.
_PV_SUPPORTED=( 8.1 8.2 8.3 8.4 )

# Same package set the installer uses (modules/40-php.sh:40-57). Kept in
# sync manually; if the installer adds/removes an extension, mirror it here.
_PV_PACKAGES=(
    fpm cli common mysql xml xmlrpc curl gd imagick mbstring zip
    bcmath intl soap redis opcache readline
)

cmd_php_version() {
    local target="${1:-}"

    section "Switch active PHP version"

    local current installed
    current=$(_php_active_version)
    installed=$(_php_installed_versions)

    # --- Picker when no arg ---------------------------------------------------
    if [[ -z "$target" ]]; then
        echo ""
        echo "  Available PHP versions (ondrej/php PPA):"
        local i=1 v label
        for v in "${_PV_SUPPORTED[@]}"; do
            label=""
            if [[ "$v" == "$current" ]]; then
                label=" (active)"
            elif echo "$installed" | grep -qx "$v"; then
                label=" (installed)"
            fi
            printf "    %d) %s%s\n" "$i" "$v" "$label"
            i=$((i + 1))
        done
        echo ""
        local reply
        read -rp "─// Select version (1-${#_PV_SUPPORTED[@]}) [0=Cancel]: " reply || return 0
        [[ "$reply" == "0" ]] && { info "Aborted."; return 0; }
        [[ "$reply" =~ ^[0-9]+$ ]] || err "Invalid selection: ${reply}"
        [[ "$reply" -ge 1 && "$reply" -le ${#_PV_SUPPORTED[@]} ]] \
            || err "Out of range: ${reply}"
        target="${_PV_SUPPORTED[$((reply - 1))]}"
    fi

    # --- Validate target ------------------------------------------------------
    [[ "$target" =~ ^[0-9]+\.[0-9]+$ ]] || err "Invalid version '${target}'. Expected MAJOR.MINOR (e.g. 8.3)."
    local v supported=0
    for v in "${_PV_SUPPORTED[@]}"; do
        [[ "$v" == "$target" ]] && { supported=1; break; }
    done
    [[ $supported -eq 1 ]] || err "Version ${target} not supported. Choose one of: ${_PV_SUPPORTED[*]}."

    if [[ "$target" == "$current" ]]; then
        info "PHP ${target} is already active."
        return 0
    fi

    # --- Confirm (expensive, multi-step) -------------------------------------
    echo ""
    echo "  This will:"
    echo "    1) Install php${target}-{fpm,cli,…} if not already present"
    echo "    2) Copy current ini + pool tuning to the new version"
    echo "    3) Rewrite vhost fastcgi_pass sockets (${current} → ${target})"
    echo "    4) Reload nginx + switch active FPM"
    echo "    5) Stop and disable php${current}-fpm (packages kept for rollback)"
    echo ""
    confirm "Switch active PHP from ${current} to ${target}?" "N" \
        || { info "Aborted."; return 0; }

    # --- Step 1: install packages if missing ---------------------------------
    if [[ ! -f "/etc/php/${target}/fpm/php.ini" ]]; then
        info "Installing PHP ${target} packages from ppa:ondrej/php..."
        if ! apt-cache show "php${target}-fpm" &>/dev/null; then
            add-apt-repository -y ppa:ondrej/php \
                || err "Failed to add ppa:ondrej/php."
            apt_update
        fi
        local pkgs=() ext
        for ext in "${_PV_PACKAGES[@]}"; do
            pkgs+=( "php${target}-${ext}" )
        done
        apt_install "${pkgs[@]}" \
            || err "apt_install failed for php${target} packages — check the logs and retry."
    else
        info "PHP ${target} already installed."
    fi

    # --- Step 2: copy forward tuning from old → new --------------------------
    info "Copying ini + pool tuning from ${current} to ${target}..."
    local old_fpm_ini="/etc/php/${current}/fpm/php.ini"
    local old_cli_ini="/etc/php/${current}/cli/php.ini"
    local new_fpm_ini="/etc/php/${target}/fpm/php.ini"
    local new_cli_ini="/etc/php/${target}/cli/php.ini"
    local old_pool="/etc/php/${current}/fpm/pool.d/www.conf"
    local new_pool="/etc/php/${target}/fpm/pool.d/www.conf"

    local ini_keys=( memory_limit upload_max_filesize post_max_size
                     max_execution_time max_input_time max_input_vars
                     date.timezone expose_php
                     opcache.enable opcache.memory_consumption
                     opcache.max_accelerated_files opcache.validate_timestamps
                     opcache.revalidate_freq )
    local k val
    for k in "${ini_keys[@]}"; do
        val=$(_php_ini_get "$old_fpm_ini" "$k")
        if [[ -n "$val" ]]; then
            [[ -f "$new_fpm_ini" ]] && _php_ini_set "$new_fpm_ini" "$k" "$val"
            [[ -f "$new_cli_ini" ]] && _php_ini_set "$new_cli_ini" "$k" "$val"
        fi
    done

    local pool_keys=( user group listen.owner listen.group
                      pm pm.max_children pm.start_servers
                      pm.min_spare_servers pm.max_spare_servers
                      pm.max_requests pm.process_idle_timeout )
    if [[ -f "$old_pool" && -f "$new_pool" ]]; then
        for k in "${pool_keys[@]}"; do
            val=$(_php_ini_get "$old_pool" "$k")
            [[ -n "$val" ]] && _php_ini_set "$new_pool" "$k" "$val"
        done
    fi

    # Safety net — if the pool wasn't carried forward, still align owner to
    # nginx user (matches _php_configure_fpm in modules/40-php.sh:60-69).
    _detect_nginx_user
    if [[ -f "$new_pool" ]]; then
        _php_ini_set "$new_pool" user          "$NGINX_USER"
        _php_ini_set "$new_pool" group         "$NGINX_USER"
        _php_ini_set "$new_pool" listen.owner  "$NGINX_USER"
        _php_ini_set "$new_pool" listen.group  "$NGINX_USER"
    fi

    # --- Step 3: start new FPM BEFORE touching nginx -------------------------
    info "Enabling + starting php${target}-fpm..."
    systemctl enable --now "php${target}-fpm" \
        || err "Failed to start php${target}-fpm — check 'journalctl -u php${target}-fpm'."

    # --- Step 4: rewrite vhost socket paths ---------------------------------
    info "Rewriting vhost fastcgi_pass socket paths..."
    local conf count=0
    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        if grep -q "/run/php/php${current}-fpm\\.sock" "$conf"; then
            sed -i "s|/run/php/php${current}-fpm\\.sock|/run/php/php${target}-fpm.sock|g" "$conf"
            count=$((count + 1))
        fi
    done
    info "Updated ${count} vhost file(s)."

    # --- Step 5: nginx -t gate + reload -------------------------------------
    if ! nginx -t 2>&1 | tail -5; then
        err "nginx -t failed after vhost rewrite. Leaving old FPM running — inspect ${NGINX_CONF_DIR}/ and retry."
    fi
    systemctl reload nginx \
        || err "systemctl reload nginx failed. Old FPM still running; new FPM is up."

    # --- Step 6: persist active version state -------------------------------
    _php_state_set php_active_version "$target"

    # --- Step 7: stop old FPM (packages kept for rollback) ------------------
    info "Stopping + disabling php${current}-fpm (packages preserved for rollback)..."
    systemctl stop "php${current}-fpm"    2>/dev/null || true
    systemctl disable "php${current}-fpm" 2>/dev/null || true

    log "PHP version switched: ${current} → ${target}. ${count} vhost(s) updated."
}
