#!/bin/bash
###############################################################################
#  manage/sftp-user-password.sh — Change a Linux user's password
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage sftp-user-password [username]
#
#  Any existing Linux user. Rejects root (use ssh-root-password instead).
#  Silent 2× entry + match check, min 12 chars. chpasswd via stdin pipe so the
#  password never lands in argv or logs.
###############################################################################

cmd_sftp_user_password() {
    local user="${1:-}"

    command_exists chpasswd || err "chpasswd not found (install the 'passwd' package)."

    section "Change user password"

    if [[ -z "$user" ]]; then
        read -rp "─// Username [0=Cancel]: " user || { info "Aborted."; return 0; }
    fi
    [[ "$user" == "0" ]] && { info "Aborted."; return 0; }
    [[ -n "$user" ]] || { warn "No username entered."; return 0; }

    if [[ "$user" == "root" ]]; then
        err "Use 'lemp-manage ssh-root-password' for the root account."
    fi

    if ! id -u "$user" &>/dev/null; then
        err "User '${user}' does not exist. Create it first: sudo adduser ${user}"
    fi

    echo ""
    confirm "Change password for user '${user}'?" "N" || { info "Aborted."; return 0; }

    local pass1 pass2
    while true; do
        read -rsp "  New password for ${user} (min 12 chars): " pass1; echo ""
        if [[ -z "$pass1" ]]; then
            warn "Empty password not allowed."
            continue
        fi
        if [[ ${#pass1} -lt 12 ]]; then
            warn "Password too short (${#pass1} chars; minimum 12). Try again."
            continue
        fi
        read -rsp "  Confirm                               : " pass2; echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            warn "Passwords don't match. Try again."
            continue
        fi
        break
    done
    pass2=""

    if ! echo "${user}:${pass1}" | chpasswd; then
        pass1=""
        err "chpasswd failed for '${user}'. Check journalctl -xe."
    fi
    pass1=""

    log "Password updated for user '${user}'."
}
