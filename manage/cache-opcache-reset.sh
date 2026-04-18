#!/bin/bash
###############################################################################
#  manage/cache-opcache-reset.sh — Flush compiled bytecode by reloading php-fpm
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage cache-opcache-reset
#
#  FPM opcache can ONLY be reset by reloading the FPM service — a CLI
#  `php -r 'opcache_reset();'` only touches the CLI SAPI's separate cache.
#  The reload is graceful: workers drain in-flight requests before recycling.
###############################################################################

cmd_cache_opcache_reset() {
    section "Reset Zend OPcache"

    local fpm_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    [[ -f "$fpm_ini" ]] || err "PHP FPM ini not found: ${fpm_ini}."

    local state
    state=$(grep -E '^opcache\.enable\s*=' "$fpm_ini" \
        | awk -F= '{print $2}' | tr -d ' ' || true)
    if [[ "$state" == "0" ]]; then
        warn "OPcache is currently disabled — nothing to reset. Enable first: lemp-manage cache-opcache-toggle on."
        return 0
    fi

    systemctl reload "php${PHP_VERSION}-fpm" \
        || err "systemctl reload php${PHP_VERSION}-fpm failed."
    log "OPcache reset via php${PHP_VERSION}-fpm reload."
}
