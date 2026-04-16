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

    _phpmyadmin_download
    _phpmyadmin_configure
    _phpmyadmin_write_nginx_snippet

    log "phpMyAdmin installed at random path: ${PMA_PATH}"
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

_phpmyadmin_write_nginx_snippet() {
    # Snippet included by every vhost
    cat > "${NGINX_SNIPPETS_DIR}/phpmyadmin.conf" <<PMAINCEOF
location ${PMA_PATH} {
    alias ${PMA_DIR};
    index index.php;

    # Rate limit logins
    limit_req zone=admin burst=20 nodelay;

    location ~ ^${PMA_PATH}/(.+\\.php)\$ {
        alias ${PMA_DIR}/\$1;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$request_filename;
        fastcgi_read_timeout ${PHP_MAX_EXEC_TIME};
    }

    location ~* ^${PMA_PATH}/(.+\\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt|woff|woff2|ttf|svg))\$ {
        alias ${PMA_DIR}/\$1;
        expires 30d;
        access_log off;
    }
}
PMAINCEOF
}
