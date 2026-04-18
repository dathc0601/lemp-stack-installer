#!/bin/bash
###############################################################################
#  modules/70-phpmyadmin.sh — phpMyAdmin with randomized URL path
#
#  Downloads latest phpMyAdmin, configures cookie auth, generates blowfish
#  secret. URL path randomized (e.g. /pma-a3f2b1c4) for obscurity.
#  Nginx snippet created for inclusion in vhosts.
#
#  Depends on: lib/core.sh (logging, constants, NGINX_USER, PMA_PATH globals)
#              lib/utils.sh (generate_url_token)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_phpmyadmin_describe() {
    echo "phpMyAdmin — randomized URL path"
}

module_phpmyadmin_check() {
    [[ -d "$PMA_DIR" ]] && state_is_installed "phpmyadmin"
}

module_phpmyadmin_install() {
    section "Installing phpMyAdmin"

    PMA_PATH="/pma-$(generate_url_token)"
    PMA_BLOWFISH=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    PMA_AUTH_USER="admin"
    PMA_AUTH_PASS=$(generate_password 24)

    _phpmyadmin_download
    _phpmyadmin_configure
    _phpmyadmin_write_htpasswd
    _phpmyadmin_write_nginx_snippet

    log "phpMyAdmin installed at random path: ${PMA_PATH}"
    log "phpMyAdmin basic-auth user '${PMA_AUTH_USER}' written to ${PMA_HTPASSWD_FILE}"
    state_mark_installed "phpmyadmin"
}

# --- Private helpers --------------------------------------------------------

_phpmyadmin_download() {
    local pma_latest
    pma_latest=$(curl -fsSL https://www.phpmyadmin.net/home_page/version.txt | head -1)
    log "Latest phpMyAdmin: ${pma_latest}"

    if [[ ! -d "$PMA_DIR" ]]; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        (
            cd "$tmp_dir"
            wget -q "https://files.phpmyadmin.net/phpMyAdmin/${pma_latest}/phpMyAdmin-${pma_latest}-all-languages.tar.gz"
            tar -xzf "phpMyAdmin-${pma_latest}-all-languages.tar.gz"
            mv "phpMyAdmin-${pma_latest}-all-languages" "$PMA_DIR"
        )
        rm -rf "$tmp_dir"
    else
        info "phpMyAdmin already installed at $PMA_DIR"
    fi
}

_phpmyadmin_configure() {
    mkdir -p "${PMA_DIR}/tmp"
    chown -R "${NGINX_USER}:${NGINX_USER}" "$PMA_DIR"
    chmod -R 755 "$PMA_DIR"
    chmod 770 "${PMA_DIR}/tmp"

    render_template "phpmyadmin-config.inc.php.tpl" \
        "PMA_BLOWFISH" "$PMA_BLOWFISH" \
        "PMA_DIR" "$PMA_DIR" \
        > "${PMA_DIR}/config.inc.php"
    chown "${NGINX_USER}:${NGINX_USER}" "${PMA_DIR}/config.inc.php"
    chmod 640 "${PMA_DIR}/config.inc.php"
}

_phpmyadmin_write_htpasswd() {
    # `-c` creates; subsequent admin-apps runs update with -bB (no -c).
    # bcrypt (-B) is the strongest supported format.
    command_exists htpasswd \
        || err "htpasswd not found — 'apache2-utils' should have been installed by modules/10-base.sh"
    htpasswd -cbB "$PMA_HTPASSWD_FILE" "$PMA_AUTH_USER" "$PMA_AUTH_PASS" >/dev/null
    chown "root:${NGINX_USER}" "$PMA_HTPASSWD_FILE"
    chmod 640 "$PMA_HTPASSWD_FILE"
}

_phpmyadmin_write_nginx_snippet() {
    # Snippet included by every vhost
    render_template "nginx-phpmyadmin.conf.tpl" \
        "PMA_PATH" "$PMA_PATH" \
        "PMA_DIR" "$PMA_DIR" \
        "PHP_VERSION" "$PHP_VERSION" \
        "PHP_MAX_EXEC_TIME" "$PHP_MAX_EXEC_TIME" \
        "PMA_HTPASSWD_FILE" "$PMA_HTPASSWD_FILE" \
        > "${NGINX_SNIPPETS_DIR}/phpmyadmin.conf"
}
