#!/bin/bash
###############################################################################
#  manage/cache-clear.sh — Flush every active cache at once
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage cache-clear
#
#  Each step is a no-op if its service is inactive. Memcached has no native
#  flush CLI shipped with the server package, so we restart it (sub-second
#  blip) rather than add libmemcached-tools or netcat as a dependency.
###############################################################################

cmd_cache_clear() {
    section "Clear all caches"

    confirm "Flush Redis + Memcached + reset OPcache? Active sessions may be logged out." "N" \
        || { info "Aborted."; return 0; }

    local flushed=()

    if command_exists redis-cli && systemctl is-active --quiet redis-server 2>/dev/null; then
        if redis-cli FLUSHALL >/dev/null 2>&1; then
            flushed+=("Redis")
        else
            warn "redis-cli FLUSHALL failed — redis-server may be unreachable."
        fi
    fi

    if command_exists memcached && systemctl is-active --quiet memcached 2>/dev/null; then
        if systemctl restart memcached; then
            flushed+=("Memcached")
        else
            warn "memcached restart failed."
        fi
    fi

    local fpm_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    if [[ -f "$fpm_ini" ]]; then
        local opc
        opc=$(grep -E '^opcache\.enable\s*=' "$fpm_ini" \
            | awk -F= '{print $2}' | tr -d ' ' || true)
        if [[ "$opc" == "1" ]]; then
            if systemctl reload "php${PHP_VERSION}-fpm"; then
                flushed+=("OPcache")
            else
                warn "php${PHP_VERSION}-fpm reload failed."
            fi
        fi
    fi

    if [[ ${#flushed[@]} -eq 0 ]]; then
        info "No active caches found — nothing to clear."
    else
        log "Cleared: ${flushed[*]}."
    fi
}
