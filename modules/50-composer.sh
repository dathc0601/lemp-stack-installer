#!/bin/bash
###############################################################################
#  modules/50-composer.sh — Composer (PHP package manager)
#
#  Downloads installer with SHA384 checksum verification.
#  Installs to /usr/local/bin/composer.
#
#  Depends on: lib/core.sh (logging, command_exists, err)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_composer_describe() {
    echo "Composer — verified install"
}

module_composer_check() {
    command_exists composer && state_is_installed "composer"
}

module_composer_install() {
    section "Installing Composer"
    if command_exists composer; then
        info "Composer already installed: $(composer --version 2>&1)"
        state_mark_installed "composer"
        return
    fi

    local expected actual
    expected="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    actual="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
    if [[ "$expected" != "$actual" ]]; then
        rm -f composer-setup.php
        err "Composer installer checksum mismatch — possible tampering."
    fi
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
    rm -f composer-setup.php
    log "Composer installed: $(composer --version 2>&1)"
    state_mark_installed "composer"
}
