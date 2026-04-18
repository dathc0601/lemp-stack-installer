#!/bin/bash
###############################################################################
#  manage/cache-redis-toggle.sh — Enable/disable the redis-server service
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage cache-redis-toggle [on|off]
#    No arg: flip current state. on|enable: start + boot. off|disable: stop.
###############################################################################

cmd_cache_redis_toggle() {
    local arg="${1:-}"

    section "Toggle Redis service"

    command_exists redis-server || err "redis-server not installed."

    local current target
    # Use --quiet + exit code rather than parsing stdout: Ubuntu's redis
    # package installs a `redis.service` alias that `disable --now` removes,
    # after which `systemctl is-active redis-server` prints two lines.
    if systemctl is-active --quiet redis-server; then
        current="active"
    else
        current="inactive"
    fi

    case "$arg" in
        on|enable)   target="active"   ;;
        off|disable) target="inactive" ;;
        "")
            if [[ "$current" == "active" ]]; then
                target="inactive"
            else
                target="active"
            fi
            ;;
        *) err "Invalid argument '${arg}'. Expected: on|off|enable|disable." ;;
    esac

    if [[ "$target" == "$current" ]]; then
        info "Redis already ${current}. Nothing to do."
        return 0
    fi

    if [[ "$target" == "inactive" ]]; then
        confirm "Stop redis-server? Any site using Redis object cache will lose cached objects." "N" \
            || { info "Aborted."; return 0; }
        systemctl disable --now redis-server \
            || err "systemctl disable --now redis-server failed."
    else
        systemctl enable --now redis-server \
            || err "systemctl enable --now redis-server failed."
    fi

    local new_state
    if systemctl is-active --quiet redis-server; then
        new_state="active"
    else
        new_state="inactive"
    fi
    [[ "$new_state" == "$target" ]] \
        || err "Service did not reach expected state: ${new_state} != ${target}."
    log "Redis ${target}."
}
