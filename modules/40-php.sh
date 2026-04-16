#!/bin/bash
###############################################################################
#  modules/40-php.sh — PHP 8.4 + extensions + FPM configuration
#
#  Installs from ppa:ondrej/php. Aligns FPM pool user to nginx user.
#  Tunes php.ini (upload limits, OPcache, expose_php=Off).
#
#  Depends on: lib/core.sh (logging, constants, command_exists, NGINX_USER)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_php_describe() {
    echo "PHP ${PHP_VERSION} — FPM, extensions, tuned"
}

module_php_check() {
    command_exists "php${PHP_VERSION}" && state_is_installed "php"
}

module_php_install() {
    section "Installing PHP ${PHP_VERSION}"
    _php_install_packages
    _php_configure_fpm
    _php_tune_ini
    systemctl enable --now "php${PHP_VERSION}-fpm"
    systemctl restart "php${PHP_VERSION}-fpm"
    log "PHP installed: $(php -v | head -1)"
    state_mark_installed "php"
}

# --- Private helpers --------------------------------------------------------

_php_install_packages() {
    if ! command_exists "php${PHP_VERSION}"; then
        add-apt-repository -y ppa:ondrej/php
        apt_update
    fi

    apt_install \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-xmlrpc" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-imagick" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-soap" \
        "php${PHP_VERSION}-redis" \
        "php${PHP_VERSION}-opcache" \
        "php${PHP_VERSION}-readline"
}

_php_configure_fpm() {
    local pool="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    [[ -f "$pool" ]] || { warn "PHP-FPM pool config not found."; return; }

    info "Aligning PHP-FPM pool to user '$NGINX_USER'..."
    sed -i "s/^user = .*/user = ${NGINX_USER}/"               "$pool"
    sed -i "s/^group = .*/group = ${NGINX_USER}/"             "$pool"
    sed -i "s/^listen.owner = .*/listen.owner = ${NGINX_USER}/" "$pool"
    sed -i "s/^listen.group = .*/listen.group = ${NGINX_USER}/" "$pool"
}

_php_tune_ini() {
    local ini_file
    for sapi in "fpm" "cli"; do
        ini_file="/etc/php/${PHP_VERSION}/${sapi}/php.ini"
        [[ -f "$ini_file" ]] || continue
        info "Tuning $ini_file"
        sed -i "s/^upload_max_filesize.*/upload_max_filesize = ${PHP_UPLOAD_MAX}/" "$ini_file"
        sed -i "s/^post_max_size.*/post_max_size = ${PHP_POST_MAX}/" "$ini_file"
        sed -i "s/^max_execution_time.*/max_execution_time = ${PHP_MAX_EXEC_TIME}/" "$ini_file"
        sed -i "s/^max_input_time.*/max_input_time = ${PHP_MAX_INPUT_TIME}/" "$ini_file"
        sed -i "s/^memory_limit.*/memory_limit = ${PHP_MEMORY_LIMIT}/" "$ini_file"
        sed -i "s/^;*max_input_vars.*/max_input_vars = ${PHP_MAX_INPUT_VARS}/" "$ini_file"
        # OPcache
        sed -i "s/^;*opcache.enable=.*/opcache.enable=1/" "$ini_file"
        sed -i "s/^;*opcache.memory_consumption=.*/opcache.memory_consumption=256/" "$ini_file"
        sed -i "s/^;*opcache.max_accelerated_files=.*/opcache.max_accelerated_files=20000/" "$ini_file"
        sed -i "s/^;*opcache.validate_timestamps=.*/opcache.validate_timestamps=1/" "$ini_file"
        sed -i "s/^;*opcache.revalidate_freq=.*/opcache.revalidate_freq=2/" "$ini_file"
        # Hide PHP version from headers
        sed -i "s/^expose_php.*/expose_php = Off/" "$ini_file"
    done
}
