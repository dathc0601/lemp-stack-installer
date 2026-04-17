#!/bin/bash
###############################################################################
#  manage/ssh-root-password.sh — Change the root account password
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssh-root-password
#
#  Silent 2× entry + match check, min 12 chars. Uses chpasswd so the password
#  never appears in argv, ps, or the log file. No auto-generate — root must be
#  human-memorizable (can't be rotated blindly without console/rescue access).
###############################################################################

# Prompt twice, enforce min length, set PASSWORD_OUT via nameref. Prompts go to
# stderr via read -rsp so the caller can safely ignore stdout.
_ssh_prompt_new_password() {
    local -n out_ref="$1"
    local label="$2"
    local pass1 pass2
    while true; do
        read -rsp "  New ${label} password (min 12 chars): " pass1; echo ""
        if [[ -z "$pass1" ]]; then
            warn "Empty password not allowed."
            continue
        fi
        if [[ ${#pass1} -lt 12 ]]; then
            warn "Password too short (${#pass1} chars; minimum 12). Try again."
            continue
        fi
        read -rsp "  Confirm                           : " pass2; echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            warn "Passwords don't match. Try again."
            continue
        fi
        out_ref="$pass1"
        # Clear locals so the password isn't sitting in the shell's memory longer
        # than necessary (best-effort — bash can't truly zero memory).
        pass1=""
        pass2=""
        return 0
    done
}

cmd_ssh_root_password() {
    command_exists chpasswd || err "chpasswd not found (install the 'passwd' package)."

    section "Change root password"
    warn "If you lose SSH key access AND forget this password, recovery"
    warn "requires console/rescue access via your hosting provider."
    echo ""
    confirm "Change the root password now?" "N" || { info "Aborted."; return 0; }

    local pass=""
    _ssh_prompt_new_password pass "root"

    if ! echo "root:${pass}" | chpasswd; then
        pass=""
        err "chpasswd failed. Check journalctl -xe."
    fi
    pass=""  # drop reference immediately after use

    log "Root password updated."
}
