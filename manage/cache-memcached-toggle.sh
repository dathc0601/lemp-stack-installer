#!/bin/bash
###############################################################################
#  manage/cache-memcached-toggle.sh — Enable/disable the memcached service
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage cache-memcached-toggle [on|off]
#    No arg: flip current state. on|enable: start + boot. off|disable: stop.
###############################################################################

cmd_cache_memcached_toggle() {
    local arg="${1:-}"

    section "Toggle Memcached service"

    command_exists memcached \
        || err "Memcached not installed. Re-run bootstrap: curl -fsSL https://raw.githubusercontent.com/dathc0601/lemp-stack-installer/main/bootstrap.sh | sudo bash"

    local current target
    # Use --quiet + exit code rather than parsing stdout — matches the
    # redis-toggle pattern and sidesteps any unit-alias stdout quirks.
    if systemctl is-active --quiet memcached; then
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
        info "Memcached already ${current}. Nothing to do."
        return 0
    fi

    if [[ "$target" == "inactive" ]]; then
        confirm "Stop memcached? Any site using it for session/object caching will lose cached data." "N" \
            || { info "Aborted."; return 0; }
        systemctl disable --now memcached \
            || err "systemctl disable --now memcached failed."
    else
        systemctl enable --now memcached \
            || err "systemctl enable --now memcached failed."
    fi

    local new_state
    if systemctl is-active --quiet memcached; then
        new_state="active"
    else
        new_state="inactive"
    fi
    [[ "$new_state" == "$target" ]] \
        || err "Service did not reach expected state: ${new_state} != ${target}."
    log "Memcached ${target}."
}
