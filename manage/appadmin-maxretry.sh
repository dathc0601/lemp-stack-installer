#!/bin/bash
###############################################################################
#  manage/appadmin-maxretry.sh — Tune fail2ban [nginx-http-auth] maxretry
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-maxretry [N]
#
#  Independent from the SSH menu's fail2ban-maxretry (which tunes [DEFAULT]).
#  This adds/updates a section-local override in [nginx-http-auth] so the two
#  menus don't step on each other.
###############################################################################

readonly _APPADMIN_JAIL_LOCAL="/etc/fail2ban/jail.local"

# Print the current [DEFAULT] maxretry (used as fallback when [nginx-http-auth]
# has no override yet).
_appadmin_read_default_maxretry() {
    awk '
        /^\[DEFAULT\]/ { f = 1; next }
        /^\[/          { f = 0 }
        f && /^[[:space:]]*maxretry[[:space:]]*=/ {
            sub(/.*=[[:space:]]*/, ""); print; exit
        }
    ' "$_APPADMIN_JAIL_LOCAL" || true
}

# Print the current [nginx-http-auth] maxretry override (empty if none).
_appadmin_read_http_maxretry() {
    awk '
        /^\[nginx-http-auth\]/ { f = 1; next }
        /^\[/                  { f = 0 }
        f && /^[[:space:]]*maxretry[[:space:]]*=/ {
            sub(/.*=[[:space:]]*/, ""); print; exit
        }
    ' "$_APPADMIN_JAIL_LOCAL" || true
}

# Return 0 if [nginx-http-auth] section has its own maxretry; 1 otherwise.
_appadmin_http_has_override() {
    awk '
        /^\[nginx-http-auth\]/ { f = 1; next }
        /^\[/                  { f = 0 }
        f && /^[[:space:]]*maxretry[[:space:]]*=/ { found = 1; exit }
        END                    { exit !found }
    ' "$_APPADMIN_JAIL_LOCAL"
}

cmd_appadmin_maxretry() {
    local new="${1:-}"

    command_exists fail2ban-client \
        || err "fail2ban not installed. Run the installer first."
    [[ -f "$_APPADMIN_JAIL_LOCAL" ]] \
        || err "Config missing: ${_APPADMIN_JAIL_LOCAL}. Re-run the installer's fail2ban module."
    grep -q '^\[nginx-http-auth\]' "$_APPADMIN_JAIL_LOCAL" \
        || err "[nginx-http-auth] section missing from ${_APPADMIN_JAIL_LOCAL}."

    section "Adjust HTTP-auth max retries (phpMyAdmin basic-auth)"

    local override default current
    override=$(_appadmin_read_http_maxretry)
    default=$(_appadmin_read_default_maxretry)
    default="${default:-5}"
    if [[ -n "$override" ]]; then
        current="$override"
        info "Current [nginx-http-auth] maxretry: ${current} (section override)"
    else
        current="$default"
        info "Current [nginx-http-auth] maxretry: ${current} (inherited from [DEFAULT])"
    fi
    echo ""

    if [[ -z "$new" ]]; then
        read -rp "─// New maxretry value (1-20) [0=Cancel]: " new \
            || { info "Aborted."; return 0; }
    fi

    [[ "$new" == "0" ]] && { info "Aborted."; return 0; }
    [[ "$new" =~ ^[0-9]+$ ]] || err "Invalid value: '${new}'. Must be an integer."
    [[ "$new" -ge 1 && "$new" -le 20 ]] \
        || err "Out of range: ${new}. Must be between 1 and 20."

    if [[ "$new" == "$current" && -n "$override" ]]; then
        info "Already ${new} — nothing to change."
        return 0
    fi

    confirm "Set [nginx-http-auth] maxretry to ${new}?" "Y" \
        || { info "Aborted."; return 0; }

    if _appadmin_http_has_override; then
        # Update existing — section-range sed limits scope to [nginx-http-auth]
        sed -i "/^\[nginx-http-auth\]/,/^\[/ s/^maxretry[[:space:]]*=.*/maxretry = ${new}/" \
            "$_APPADMIN_JAIL_LOCAL" \
            || err "sed update failed in ${_APPADMIN_JAIL_LOCAL}."
    else
        # Insert a new key right after the section header
        sed -i "/^\[nginx-http-auth\]/a maxretry = ${new}" \
            "$_APPADMIN_JAIL_LOCAL" \
            || err "sed insert failed in ${_APPADMIN_JAIL_LOCAL}."
    fi

    # Verify
    local after
    after=$(_appadmin_read_http_maxretry)
    [[ "$after" == "$new" ]] \
        || err "Verification failed: expected maxretry=${new}, got '${after}'. Inspect ${_APPADMIN_JAIL_LOCAL}."

    info "Reloading fail2ban..."
    if ! systemctl reload fail2ban; then
        warn "reload failed; trying restart..."
        systemctl restart fail2ban || err "fail2ban restart failed. Check: journalctl -u fail2ban"
    fi

    local live
    live=$(fail2ban-client get nginx-http-auth maxretry 2>/dev/null || true)
    [[ -n "$live" ]] && info "fail2ban-client reports [nginx-http-auth] maxretry = ${live}"

    log "HTTP-auth maxretry set to ${new} (applies to phpMyAdmin basic-auth failures)."
}
