#!/bin/bash
###############################################################################
#  manage/php-config.sh — Edit common php.ini directives (interactive)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage php-config
#
#  Covers the six knobs the installer tunes in modules/40-php.sh: memory_limit,
#  upload_max_filesize, post_max_size, max_execution_time, max_input_vars,
#  date.timezone. Applies changes to both FPM and CLI ini files (parity with
#  _php_tune_ini) and reloads FPM.
###############################################################################

# Validate a memory / size value (e.g. "128M", "1G", "512"). Pure digits
# interpreted as bytes by PHP; with suffix K/M/G interpreted accordingly.
_pc_valid_size() { [[ "$1" =~ ^[0-9]+[KMG]?$ ]]; }

# Validate a non-negative integer within a sane cap (for exec time, input vars).
_pc_valid_int() {
    local v="$1" cap="$2"
    [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -le "$cap" ]]
}

# Validate a timezone string against the zoneinfo DB.
_pc_valid_tz() {
    local tz="$1"
    [[ -z "$tz" ]] && return 1
    [[ "$tz" == "UTC" ]] && return 0
    [[ -f "/usr/share/zoneinfo/${tz}" ]]
}

cmd_php_config() {
    section "Edit PHP ini (common directives)"

    local fpm_ini cli_ini
    fpm_ini=$(_php_ini_file fpm)
    cli_ini=$(_php_ini_file cli)
    [[ -f "$fpm_ini" ]] || err "FPM php.ini not found: ${fpm_ini}"
    [[ -f "$cli_ini" ]] || warn "CLI php.ini not found: ${cli_ini} (will skip CLI updates)"

    # --- Read current values ------------------------------------------------
    local keys=( memory_limit upload_max_filesize post_max_size \
                 max_execution_time max_input_vars date.timezone )
    declare -A current new
    local k
    for k in "${keys[@]}"; do
        current[$k]=$(_php_ini_get "$fpm_ini" "$k")
        new[$k]="${current[$k]}"
    done

    echo ""
    echo "  Current (from ${fpm_ini}):"
    for k in "${keys[@]}"; do
        printf "    %-22s = %s\n" "$k" "${current[$k]:-(unset)}"
    done
    echo ""
    echo "  Press Enter to keep each current value, or type a new one."
    echo ""

    # --- Prompt per key with per-type validation ----------------------------
    local reply
    for k in "${keys[@]}"; do
        while true; do
            read -rp "  ${k} [${current[$k]:-unset}]: " reply || return 0
            if [[ -z "$reply" ]]; then
                break
            fi
            case "$k" in
                memory_limit|upload_max_filesize|post_max_size)
                    if _pc_valid_size "$reply"; then new[$k]="$reply"; break; fi
                    warn "Expected integer with optional K/M/G suffix (e.g. 256M, 1G)."
                    ;;
                max_execution_time)
                    if _pc_valid_int "$reply" 86400; then new[$k]="$reply"; break; fi
                    warn "Expected integer 0-86400 (seconds)."
                    ;;
                max_input_vars)
                    if _pc_valid_int "$reply" 100000; then new[$k]="$reply"; break; fi
                    warn "Expected integer 0-100000."
                    ;;
                date.timezone)
                    if _pc_valid_tz "$reply"; then new[$k]="$reply"; break; fi
                    warn "Unknown timezone. Examples: UTC, America/New_York, Asia/Ho_Chi_Minh."
                    ;;
            esac
        done
    done

    # --- Show diff + confirm ------------------------------------------------
    local changed=0
    echo ""
    echo "  Proposed changes:"
    for k in "${keys[@]}"; do
        if [[ "${new[$k]}" != "${current[$k]}" ]]; then
            printf "    %-22s : %s  →  %s\n" "$k" "${current[$k]:-unset}" "${new[$k]}"
            changed=$((changed + 1))
        fi
    done
    if [[ $changed -eq 0 ]]; then
        info "No changes."
        return 0
    fi
    echo ""
    confirm "Apply ${changed} change(s) to FPM + CLI php.ini and reload FPM?" "Y" \
        || { info "Aborted."; return 0; }

    # --- Write --------------------------------------------------------------
    local ini sapi
    for sapi in fpm cli; do
        ini=$(_php_ini_file "$sapi")
        [[ -f "$ini" ]] || continue
        for k in "${keys[@]}"; do
            if [[ "${new[$k]}" != "${current[$k]}" ]]; then
                _php_ini_set "$ini" "$k" "${new[$k]}"
            fi
        done
    done

    # --- Reload FPM ---------------------------------------------------------
    local svc
    svc=$(_php_fpm_service)
    systemctl reload "$svc" \
        || err "systemctl reload ${svc} failed — check 'journalctl -u ${svc}'."

    # --- Log (only the changed keys) ----------------------------------------
    local log_parts=""
    for k in "${keys[@]}"; do
        if [[ "${new[$k]}" != "${current[$k]}" ]]; then
            log_parts+="${k}=${new[$k]}, "
        fi
    done
    log "PHP ini updated: ${log_parts%, }. Reloaded ${svc}."
}
