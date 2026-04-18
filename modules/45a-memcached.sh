#!/bin/bash
###############################################################################
#  modules/45a-memcached.sh — Memcached server + php-memcached extension
#
#  Ships enabled-by-default. Binds to 127.0.0.1; UFW blocks 11211 from WAN.
#  Alphabetical ordering places it between 45-redis.sh and 50-composer.sh.
#
#  Depends on: lib/core.sh (logging, command_exists, PHP_VERSION)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_memcached_describe() {
    echo "Memcached server + php-memcached extension"
}

module_memcached_check() {
    command_exists memcached && state_is_installed "memcached"
}

module_memcached_install() {
    section "Installing Memcached"
    apt_install memcached "php${PHP_VERSION}-memcached"
    # Ubuntu 22.04/24.04 both ship with -l 127.0.0.1 already, but set
    # explicitly so any future package update can't silently expose 11211.
    sed -i 's/^-l .*/-l 127.0.0.1/' /etc/memcached.conf
    systemctl enable --now memcached
    # Restart FPM so PHP loads the new extension
    systemctl restart "php${PHP_VERSION}-fpm"
    log "Memcached installed: $(memcached -V | awk '{print $2}' || true)"
    state_mark_installed "memcached"
}
