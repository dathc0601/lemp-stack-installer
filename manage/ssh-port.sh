#!/bin/bash
###############################################################################
#  manage/ssh-port.sh — Change the SSH listen port (two-phase safety gate)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssh-port [new_port]
#
#  Two-phase flow to prevent lock-out:
#    Phase 1 (additive) — add new port; keep old port listening.
#    Verification gate — user logs in on new port from another terminal.
#    Phase 2 (destructive) — close old port in UFW + sshd + fail2ban.
#  On gate-decline or verification failure, rollback restores pre-state.
###############################################################################

readonly _SSH_DROPIN_FINAL="/etc/ssh/sshd_config.d/99-lemp-port.conf"
readonly _SSH_DROPIN_PHASE1="/etc/ssh/sshd_config.d/99-lemp-port-phase1.conf"
readonly _F2B_JAIL="/etc/fail2ban/jail.local"

# Find UFW rule indices matching "<port>/tcp" (v4+v6), return newline-separated.
_ssh_port_ufw_find() {
    local port="$1"
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[[[:space:]]*([0-9]+)\][[:space:]]+${port}/tcp ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done < <(ufw status numbered 2>/dev/null || true)
}

# Delete any UFW rule matching <port>/tcp (v4 and v6).
# Delete in descending index order so earlier deletes don't shift later ones.
_ssh_port_ufw_delete() {
    local port="$1"
    local numbers
    numbers=$(_ssh_port_ufw_find "$port" | sort -rn)
    if [[ -z "$numbers" ]]; then
        warn "No UFW rule found for ${port}/tcp — skipping."
        return 0
    fi
    local n
    while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        if ! ufw --force delete "$n" >/dev/null 2>&1; then
            warn "ufw --force delete ${n} failed (rule may already be gone)."
        fi
    done <<< "$numbers"
}

# Poll ss for a TCP listener on $1. Returns 0 if seen within $2 seconds.
_ssh_port_wait_listening() {
    local port="$1"
    local timeout="${2:-5}"
    local i
    for (( i = 0; i < timeout * 2; i++ )); do
        if ss -tlnH 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {f=1} END {exit !f}'; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# Rollback Phase 1: drop the phase1 drop-in, reload ssh, close the new UFW rule.
_ssh_port_rollback_phase1() {
    local new_port="$1"
    warn "Rolling back Phase 1..."
    rm -f "$_SSH_DROPIN_PHASE1"
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    _ssh_port_ufw_delete "$new_port"
    info "Rollback complete. SSH is back on its previous port only."
}

cmd_ssh_port() {
    local new_port="${1:-}"

    command_exists sshd || err "sshd not installed."
    command_exists ufw  || err "ufw not installed."
    command_exists ss   || err "ss (iproute2) not found."

    # Socket-activated SSH (Debian 12+ style) bypasses sshd_config's Port directive.
    # Ubuntu 22.04/24.04 LTS don't default to it, but a user may have enabled it.
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        err "ssh.socket is active (socket-activated sshd). This tool edits sshd_config drop-ins
       which are ignored under socket activation. Disable ssh.socket first:
           systemctl disable --now ssh.socket && systemctl enable --now ssh
       then re-run this command."
    fi

    # Detect current port (populates SSH_PORT global)
    detect_ssh_port
    local old_port="${SSH_PORT}"

    section "Change SSH port"
    info "Current SSH port: ${old_port}"
    echo ""

    if [[ -z "$new_port" ]]; then
        read -rp "─// New SSH port (1024-65535) [0=Cancel]: " new_port || { info "Aborted."; return 0; }
    fi
    [[ "$new_port" == "0" ]] && { info "Aborted."; return 0; }
    [[ "$new_port" =~ ^[0-9]+$ ]] || err "Invalid port: '${new_port}'. Must be an integer."
    [[ "$new_port" -ge 1024 && "$new_port" -le 65535 ]] \
        || err "Out of range: ${new_port}. Must be 1024-65535."
    [[ "$new_port" == "$old_port" ]] \
        && { info "New port equals current port — nothing to change."; return 0; }

    # Warn on well-known service ports that almost certainly conflict with this stack.
    case "$new_port" in
        80|443|3306|6379|8080|9000)
            warn "Port ${new_port} is reserved for HTTP/HTTPS/MariaDB/Redis/etc. — this will break the stack."
            confirm "Really use ${new_port} anyway?" "N" || { info "Aborted."; return 0; }
            ;;
    esac

    # Something else listening already?
    if ss -tlnH 2>/dev/null | awk -v p=":$new_port" '$4 ~ p"$" {f=1} END {exit !f}'; then
        err "Port ${new_port} is already in use. Pick another."
    fi

    echo ""
    warn "Changing SSH port is risky. You MUST keep this session open until you've"
    warn "verified login on the new port from a separate terminal."
    warn "This command opens the new port WITHOUT closing the old one, then waits"
    warn "for you to confirm a successful test login before closing the old port."
    echo ""
    confirm "Proceed to Phase 1 (open port ${new_port} alongside ${old_port})?" "N" \
        || { info "Aborted."; return 0; }

    # ---- Phase 1: additive ---------------------------------------------------
    info "Phase 1: writing sshd drop-in for ports ${old_port} and ${new_port}..."
    umask 022
    cat > "$_SSH_DROPIN_PHASE1" <<DROPIN
# Managed by lemp-manage ssh-port (Phase 1 — transitional)
# Keeps both the old and new SSH port listening until Phase 2 commits.
Port ${old_port}
Port ${new_port}
DROPIN
    chmod 644 "$_SSH_DROPIN_PHASE1"

    if ! sshd -t 2>&1; then
        rm -f "$_SSH_DROPIN_PHASE1"
        err "sshd -t rejected the Phase 1 drop-in. No changes kept."
    fi

    info "Opening ${new_port}/tcp in UFW..."
    if ! ufw allow "${new_port}/tcp" comment "SSH (new)" >/dev/null; then
        rm -f "$_SSH_DROPIN_PHASE1"
        err "ufw allow ${new_port}/tcp failed."
    fi

    info "Reloading ssh..."
    if ! (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null); then
        _ssh_port_rollback_phase1 "$new_port"
        err "systemctl reload ssh failed."
    fi

    info "Waiting for port ${new_port} to start listening..."
    if ! _ssh_port_wait_listening "$new_port" 5; then
        _ssh_port_rollback_phase1 "$new_port"
        err "Port ${new_port} is not listening after reload. Check: journalctl -u ssh"
    fi

    echo ""
    log "Phase 1 complete. SSH now listens on BOTH ${old_port} and ${new_port}."
    echo ""
    warn "===================  TEST LOGIN NOW  ==================="
    warn "Open a SEPARATE terminal and run:"
    warn "    ssh -p ${new_port} <your-user>@<this-host>"
    warn "Do NOT close this session until you confirm the test login works."
    warn "========================================================"
    echo ""

    # ---- Phase 2 gate --------------------------------------------------------
    if ! confirm "Did the test login on port ${new_port} succeed?" "N"; then
        _ssh_port_rollback_phase1 "$new_port"
        info "Rolled back. SSH is still on ${old_port}."
        return 0
    fi

    # ---- Phase 2: destructive ------------------------------------------------
    info "Phase 2: committing ${new_port} as the sole SSH port..."

    # Replace the transitional drop-in with a final one that holds only the new port.
    cat > "$_SSH_DROPIN_FINAL" <<DROPIN
# Managed by lemp-manage ssh-port
Port ${new_port}
DROPIN
    chmod 644 "$_SSH_DROPIN_FINAL"
    rm -f "$_SSH_DROPIN_PHASE1"

    if ! sshd -t 2>&1; then
        # Restore the phase1 drop-in so the user isn't stranded
        cat > "$_SSH_DROPIN_PHASE1" <<DROPIN
Port ${old_port}
Port ${new_port}
DROPIN
        rm -f "$_SSH_DROPIN_FINAL"
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        err "sshd -t rejected Phase 2 config. Restored Phase 1 state; old port still open."
    fi

    if ! (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null); then
        warn "systemctl reload ssh failed on Phase 2 — old port may still be listening."
        warn "Inspect with: ss -tlnH | grep -E ':(${old_port}|${new_port})\b'"
    fi

    info "Closing ${old_port}/tcp in UFW..."
    _ssh_port_ufw_delete "$old_port"

    # Update fail2ban [sshd] jail — section-aware sed to avoid touching unrelated jails.
    if [[ -f "$_F2B_JAIL" ]]; then
        info "Updating fail2ban [sshd] jail to port ${new_port}..."
        if sed -i "/^\[sshd\]/,/^\[/ s/^port[[:space:]]*=.*/port    = ${new_port}/" "$_F2B_JAIL"; then
            systemctl reload fail2ban 2>/dev/null \
                || systemctl restart fail2ban 2>/dev/null \
                || warn "fail2ban reload failed. Check: journalctl -u fail2ban"
        else
            warn "sed failed on ${_F2B_JAIL}; fail2ban still watches old port."
        fi
    fi

    # Update session global so subsequent menu actions see the new port.
    SSH_PORT="$new_port"

    echo ""
    log "SSH port changed from ${old_port} to ${new_port}."
    log "sshd drop-in:    ${_SSH_DROPIN_FINAL}"
    log "UFW, fail2ban, and session SSH_PORT are all in sync."
}
