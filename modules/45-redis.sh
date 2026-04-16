#!/bin/bash
###############################################################################
#  modules/45-redis.sh — Redis server
#
#  Installs redis-server package and enables the service.
#  The php-redis extension is installed by the PHP module (40-php.sh).
#
#  Depends on: lib/core.sh (logging, command_exists, apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_redis_describe() {
    echo "Redis server"
}

module_redis_check() {
    command_exists redis-server && state_is_installed "redis"
}

module_redis_install() {
    section "Installing Redis"
    apt_install redis-server
    systemctl enable --now redis-server
    # awk '{print $3}' extracts "v=7.0.15" from redis-server --version output;
    # || true guards against version parse failure under set -e
    log "Redis installed: $(redis-server --version | awk '{print $3}' || true)"
    state_mark_installed "redis"
}
