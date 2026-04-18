#!/bin/bash
###############################################################################
#  manage/cache-opcache-toggle.sh — Enable/disable Zend OPcache
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage cache-opcache-toggle [on|off]
#
#  Edits opcache.enable in both FPM and CLI php.ini, then reloads php-fpm.
#  Matches the install-time _php_tune_ini loop (modules/40-php.sh:73-91).
###############################################################################

cmd_cache_opcache_toggle() {
    local arg="${1:-}"

    section "Toggle Zend OPcache"

    local fpm_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    [[ -f "$fpm_ini" ]] || err "PHP FPM ini not found: ${fpm_ini}."

    local current_val
    current_val=$(grep -E '^opcache\.enable\s*=' "$fpm_ini" \
        | awk -F= '{print $2}' | tr -d ' ' || true)
    case "$current_val" in
        1|0) ;;
        *)   err "Cannot read opcache.enable from ${fpm_ini}. Manual inspection required." ;;
    esac

    local target_val target_label
    case "$arg" in
        on|enable)   target_val="1" ;;
        off|disable) target_val="0" ;;
        "")
            if [[ "$current_val" == "1" ]]; then
                target_val="0"
            else
                target_val="1"
            fi
            ;;
        *) err "Invalid argument '${arg}'. Expected: on|off|enable|disable." ;;
    esac
    if [[ "$target_val" == "1" ]]; then
        target_label="enabled"
    else
        target_label="disabled"
    fi

    if [[ "$target_val" == "$current_val" ]]; then
        local current_label
        if [[ "$current_val" == "1" ]]; then
            current_label="enabled"
        else
            current_label="disabled"
        fi
        info "OPcache already ${current_label}. Nothing to do."
        return 0
    fi

    if [[ "$target_val" == "0" ]]; then
        confirm "Disable OPcache? Every PHP request will be slower until re-enabled." "N" \
            || { info "Aborted."; return 0; }
    fi

    local sapi ini
    for sapi in "fpm" "cli"; do
        ini="/etc/php/${PHP_VERSION}/${sapi}/php.ini"
        [[ -f "$ini" ]] || continue
        sed -i "s/^opcache\.enable=.*/opcache.enable=${target_val}/" "$ini" \
            || err "sed failed on ${ini}."
    done

    systemctl reload "php${PHP_VERSION}-fpm" \
        || err "systemctl reload php${PHP_VERSION}-fpm failed."

    # Verify via CLI SAPI — FPM runtime state can't be inspected without a web endpoint.
    local cli_val
    cli_val=$(php -r 'echo (int) ini_get("opcache.enable");' 2>/dev/null || echo "?")
    [[ "$cli_val" == "$target_val" ]] \
        || warn "CLI php reports opcache.enable=${cli_val}, expected ${target_val}."

    log "OPcache ${target_label} in FPM and CLI php.ini. Reloaded php${PHP_VERSION}-fpm."
}
