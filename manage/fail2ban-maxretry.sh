#!/bin/bash
###############################################################################
#  manage/fail2ban-maxretry.sh — Adjust fail2ban max failed-login retries
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage fail2ban-maxretry [N]
#
#  Edits /etc/fail2ban/jail.local's [DEFAULT] maxretry. Cascades via fail2ban's
#  [DEFAULT] inheritance to [sshd] and [nginx-http-auth]. [nginx-botsearch]'s
#  intentional maxretry=2 override is left alone thanks to section-aware sed.
###############################################################################

readonly _F2B_JAIL_LOCAL="/etc/fail2ban/jail.local"

# Extract maxretry from the [DEFAULT] section only (stops at the next [header]).
_f2b_read_default_maxretry() {
    awk '
        /^\[DEFAULT\]/ { in_default = 1; next }
        /^\[/         { in_default = 0 }
        in_default && /^[[:space:]]*maxretry[[:space:]]*=/ {
            sub(/.*=[[:space:]]*/, "")
            print
            exit
        }
    ' "$_F2B_JAIL_LOCAL" || true
}

cmd_fail2ban_maxretry() {
    local new="${1:-}"

    command_exists fail2ban-client || err "fail2ban not installed. Run the installer first."
    [[ -f "$_F2B_JAIL_LOCAL" ]] \
        || err "Config missing: ${_F2B_JAIL_LOCAL}. Re-run the installer's fail2ban module."

    section "Adjust fail2ban maxretry"

    local current
    current=$(_f2b_read_default_maxretry)
    current="${current:-5}"
    info "Current [DEFAULT] maxretry: ${current}"
    info "Cascades to [sshd] and [nginx-http-auth]; [nginx-botsearch] keeps its own override."
    echo ""

    if [[ -z "$new" ]]; then
        read -rp "─// New maxretry value (1-20) [0=Cancel]: " new || { info "Aborted."; return 0; }
    fi

    [[ "$new" == "0" ]] && { info "Aborted."; return 0; }
    [[ "$new" =~ ^[0-9]+$ ]] || err "Invalid value: '${new}'. Must be an integer."
    [[ "$new" -ge 1 && "$new" -le 20 ]] \
        || err "Out of range: ${new}. Must be between 1 and 20."

    if [[ "$new" == "$current" ]]; then
        info "Already ${new} — nothing to change."
        return 0
    fi

    confirm "Change [DEFAULT] maxretry from ${current} to ${new}?" "Y" \
        || { info "Aborted."; return 0; }

    # Section-aware replacement: range bounded by [DEFAULT] and the next [header]
    if ! sed -i "/^\[DEFAULT\]/,/^\[/ s/^maxretry[[:space:]]*=.*/maxretry = ${new}/" "$_F2B_JAIL_LOCAL"; then
        err "sed failed to update ${_F2B_JAIL_LOCAL}."
    fi

    # Verify the edit landed where we wanted
    local after
    after=$(_f2b_read_default_maxretry)
    [[ "$after" == "$new" ]] \
        || err "Verification failed: expected maxretry=${new}, got '${after}'. Inspect ${_F2B_JAIL_LOCAL}."

    info "Reloading fail2ban..."
    if ! systemctl reload fail2ban; then
        warn "reload failed; trying restart..."
        systemctl restart fail2ban || err "fail2ban restart failed. Check: journalctl -u fail2ban"
    fi

    # Show fail2ban-client's live view (confirms the daemon picked up the change)
    local live
    live=$(fail2ban-client get sshd maxretry 2>/dev/null || true)
    [[ -n "$live" ]] && info "fail2ban-client reports [sshd] maxretry = ${live}"

    log "fail2ban maxretry set to ${new} (affects [sshd] and [nginx-http-auth])."
}
