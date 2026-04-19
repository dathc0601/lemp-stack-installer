#!/bin/bash
###############################################################################
#  manage/php-pool.sh — Tune the shared FPM pool (www.conf)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage php-pool
#
#  Edits /etc/php/<active>/fpm/pool.d/www.conf. Per-domain pools are NOT
#  supported — our vhosts all point at one shared socket. Adding them would
#  require rewriting templates/nginx-vhost.conf.tpl + manage/add-domain.sh.
###############################################################################

_pp_valid_int() {
    local v="$1" min="$2" max="$3"
    [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -ge "$min" ]] && [[ "$v" -le "$max" ]]
}

cmd_php_pool() {
    section "Edit PHP-FPM pool (shared www.conf)"

    local pool
    pool=$(_php_pool_file)
    [[ -f "$pool" ]] || err "Pool config not found: ${pool}"

    # --- Read current values -----------------------------------------------
    local cur_pm cur_mc cur_start cur_mn cur_mx cur_req cur_idle
    cur_pm=$(_php_pool_get pm)
    cur_mc=$(_php_pool_get pm.max_children)
    cur_start=$(_php_pool_get pm.start_servers)
    cur_mn=$(_php_pool_get pm.min_spare_servers)
    cur_mx=$(_php_pool_get pm.max_spare_servers)
    cur_req=$(_php_pool_get pm.max_requests)
    cur_idle=$(_php_pool_get pm.process_idle_timeout)

    echo ""
    echo "  Current (from ${pool}):"
    printf "    %-28s = %s\n" "pm"                        "${cur_pm:-(unset)}"
    printf "    %-28s = %s\n" "pm.max_children"           "${cur_mc:-(unset)}"
    printf "    %-28s = %s\n" "pm.start_servers"          "${cur_start:-(unset)}"
    printf "    %-28s = %s\n" "pm.min_spare_servers"      "${cur_mn:-(unset)}"
    printf "    %-28s = %s\n" "pm.max_spare_servers"      "${cur_mx:-(unset)}"
    printf "    %-28s = %s\n" "pm.max_requests"           "${cur_req:-(unset)}"
    printf "    %-28s = %s\n" "pm.process_idle_timeout"   "${cur_idle:-(unset)}"
    echo ""
    echo "  Press Enter to keep each current value."
    echo ""

    # --- Prompt pm mode first (controls which sub-directives are relevant) --
    local new_pm="$cur_pm" reply
    while true; do
        read -rp "  pm [${cur_pm:-dynamic}] (dynamic|ondemand|static): " reply || return 0
        if [[ -z "$reply" ]]; then break; fi
        case "$reply" in
            dynamic|ondemand|static) new_pm="$reply"; break ;;
            *) warn "Invalid. Expected: dynamic|ondemand|static." ;;
        esac
    done

    # --- Prompt max_children (always) --------------------------------------
    local new_mc="$cur_mc"
    while true; do
        read -rp "  pm.max_children [${cur_mc:-5}]: " reply || return 0
        if [[ -z "$reply" ]]; then break; fi
        if _pp_valid_int "$reply" 1 200; then new_mc="$reply"; break; fi
        warn "Expected integer 1-200."
    done

    # --- Dynamic-only sub-directives ---------------------------------------
    local new_start="$cur_start" new_mn="$cur_mn" new_mx="$cur_mx"
    if [[ "$new_pm" == "dynamic" ]]; then
        while true; do
            read -rp "  pm.start_servers [${cur_start:-2}]: " reply || return 0
            if [[ -z "$reply" ]]; then break; fi
            if _pp_valid_int "$reply" 1 200; then new_start="$reply"; break; fi
            warn "Expected integer 1-200."
        done
        while true; do
            read -rp "  pm.min_spare_servers [${cur_mn:-1}]: " reply || return 0
            if [[ -z "$reply" ]]; then break; fi
            if _pp_valid_int "$reply" 1 200; then new_mn="$reply"; break; fi
            warn "Expected integer 1-200."
        done
        while true; do
            read -rp "  pm.max_spare_servers [${cur_mx:-3}]: " reply || return 0
            if [[ -z "$reply" ]]; then break; fi
            if _pp_valid_int "$reply" 1 200; then new_mx="$reply"; break; fi
            warn "Expected integer 1-200."
        done
    fi

    # --- max_requests (0 = never recycle) + ondemand idle timeout ----------
    local new_req="$cur_req"
    while true; do
        read -rp "  pm.max_requests [${cur_req:-500}] (0=never recycle): " reply || return 0
        if [[ -z "$reply" ]]; then break; fi
        if _pp_valid_int "$reply" 0 1000000; then new_req="$reply"; break; fi
        warn "Expected integer 0-1000000."
    done
    local new_idle="$cur_idle"
    if [[ "$new_pm" == "ondemand" ]]; then
        while true; do
            read -rp "  pm.process_idle_timeout [${cur_idle:-10s}] (e.g. 10s, 30s): " reply || return 0
            if [[ -z "$reply" ]]; then break; fi
            if [[ "$reply" =~ ^[0-9]+[smhd]?$ ]]; then new_idle="$reply"; break; fi
            warn "Expected duration like '10s', '1m', '30' (seconds)."
        done
    fi

    # --- Validate invariants (dynamic mode) ---------------------------------
    if [[ "$new_pm" == "dynamic" ]]; then
        if ! { [[ "$new_mn" -le "$new_start" ]] && [[ "$new_start" -le "$new_mx" ]] && [[ "$new_mx" -le "$new_mc" ]]; }; then
            err "Invalid dynamic pool: need min_spare(${new_mn}) ≤ start(${new_start}) ≤ max_spare(${new_mx}) ≤ max_children(${new_mc})."
        fi
    fi

    # --- Show diff + confirm ------------------------------------------------
    local changed=0
    echo ""
    echo "  Proposed changes:"
    _pp_diff() {
        local label="$1" old="$2" new="$3"
        if [[ "$old" != "$new" ]]; then
            printf "    %-28s : %s  →  %s\n" "$label" "${old:-unset}" "$new"
            changed=$((changed + 1))
        fi
    }
    _pp_diff "pm"                       "$cur_pm"    "$new_pm"
    _pp_diff "pm.max_children"          "$cur_mc"    "$new_mc"
    if [[ "$new_pm" == "dynamic" ]]; then
        _pp_diff "pm.start_servers"     "$cur_start" "$new_start"
        _pp_diff "pm.min_spare_servers" "$cur_mn"    "$new_mn"
        _pp_diff "pm.max_spare_servers" "$cur_mx"    "$new_mx"
    fi
    _pp_diff "pm.max_requests"          "$cur_req"   "$new_req"
    if [[ "$new_pm" == "ondemand" ]]; then
        _pp_diff "pm.process_idle_timeout" "$cur_idle" "$new_idle"
    fi
    unset -f _pp_diff

    if [[ $changed -eq 0 ]]; then
        info "No changes."
        return 0
    fi
    echo ""
    confirm "Apply ${changed} change(s) to ${pool} and reload FPM?" "Y" \
        || { info "Aborted."; return 0; }

    # --- Write --------------------------------------------------------------
    [[ "$new_pm"    != "$cur_pm"    ]] && _php_pool_set pm                      "$new_pm"
    [[ "$new_mc"    != "$cur_mc"    ]] && _php_pool_set pm.max_children         "$new_mc"
    if [[ "$new_pm" == "dynamic" ]]; then
        [[ "$new_start" != "$cur_start" ]] && _php_pool_set pm.start_servers     "$new_start"
        [[ "$new_mn"    != "$cur_mn"    ]] && _php_pool_set pm.min_spare_servers "$new_mn"
        [[ "$new_mx"    != "$cur_mx"    ]] && _php_pool_set pm.max_spare_servers "$new_mx"
    fi
    [[ "$new_req"   != "$cur_req"   ]] && _php_pool_set pm.max_requests         "$new_req"
    if [[ "$new_pm" == "ondemand" && "$new_idle" != "$cur_idle" ]]; then
        _php_pool_set pm.process_idle_timeout "$new_idle"
    fi

    # --- Reload FPM ---------------------------------------------------------
    local svc
    svc=$(_php_fpm_service)
    systemctl reload "$svc" \
        || err "systemctl reload ${svc} failed — check 'journalctl -u ${svc}'."

    log "PHP pool updated: pm=${new_pm}, max_children=${new_mc}. Reloaded ${svc}."
}
