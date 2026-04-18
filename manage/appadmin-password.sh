#!/bin/bash
###############################################################################
#  manage/appadmin-password.sh — Change an admin user's password
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-password [pma|fb] [username]
#
#  PMA: `htpasswd -bB` (no -c) on /etc/nginx/.htpasswd-pma.
#  FB:  `filebrowser users update <user> --password=<pass>`.
###############################################################################

# Silent 2× password prompt, min 12 chars. Stores result in the referenced var.
_appadmin_prompt_password() {
    local -n out_ref="$1"
    local label="${2:-new}"
    local pass1 pass2
    while true; do
        read -rsp "  ${label} password (min 12 chars): " pass1; echo ""
        if [[ -z "$pass1" ]]; then
            warn "Empty password not allowed."
            continue
        fi
        if [[ ${#pass1} -lt 12 ]]; then
            warn "Password too short (${#pass1} chars; minimum 12). Try again."
            continue
        fi
        read -rsp "  Confirm                         : " pass2; echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            warn "Passwords don't match. Try again."
            continue
        fi
        out_ref="$pass1"
        pass1=""; pass2=""
        return 0
    done
}

_appadmin_change_pma_password() {
    local user="$1" pass="$2"
    [[ -f "$PMA_HTPASSWD_FILE" ]] \
        || err "No htpasswd file: ${PMA_HTPASSWD_FILE}. Add a user first with appadmin-add."
    grep -q "^${user}:" "$PMA_HTPASSWD_FILE" \
        || err "User '${user}' not found in ${PMA_HTPASSWD_FILE}."
    if ! command_exists htpasswd; then
        info "Installing apache2-utils (provides htpasswd)..."
        apt_install apache2-utils \
            || err "apt_install apache2-utils failed. Install manually and retry."
    fi
    htpasswd -bB "$PMA_HTPASSWD_FILE" "$user" "$pass" >/dev/null \
        || err "htpasswd update failed."
    log "phpMyAdmin password updated for '${user}'."
}

_appadmin_change_fb_password() {
    local user="$1" pass="$2"
    command_exists filebrowser || err "filebrowser CLI not found."
    local db="${FB_DATA_DIR}/filebrowser.db"
    [[ -f "$db" ]] || err "File Browser database not found: ${db}"
    filebrowser users update "$user" --password="$pass" -d "$db" >/dev/null 2>&1 \
        || err "filebrowser users update failed — does user '${user}' exist?"
    log "File Browser password updated for '${user}'."
}

cmd_appadmin_password() {
    local app="${1:-}" user="${2:-}"

    section "Change admin password"

    # --- Pick app -------------------------------------------------------------
    if [[ -z "$app" ]]; then
        if declare -f _menu_pick_admin_app >/dev/null; then
            app=$(_menu_pick_admin_app) || { info "Aborted."; return 0; }
        else
            read -rp "─// App [pma|fb]: " app || { info "Aborted."; return 0; }
        fi
    fi
    case "$app" in
        pma|fb) ;;
        *) err "Invalid app: '${app}'. Expected 'pma' or 'fb'." ;;
    esac

    # --- Pick user ------------------------------------------------------------
    if [[ -z "$user" ]]; then
        case "$app" in
            pma)
                if declare -f _menu_pick_pma_user >/dev/null; then
                    user=$(_menu_pick_pma_user) || { info "Aborted."; return 0; }
                else
                    read -rp "─// Username: " user || { info "Aborted."; return 0; }
                fi
                ;;
            fb)
                if declare -f _menu_pick_fb_user >/dev/null; then
                    user=$(_menu_pick_fb_user) || { info "Aborted."; return 0; }
                else
                    read -rp "─// Username: " user || { info "Aborted."; return 0; }
                fi
                ;;
        esac
    fi
    [[ -n "$user" ]] || err "Empty username."

    # --- Prompt password -----------------------------------------------------
    local pass=""
    _appadmin_prompt_password pass "New"

    # --- Dispatch -------------------------------------------------------------
    case "$app" in
        pma) _appadmin_change_pma_password "$user" "$pass" ;;
        fb)  _appadmin_change_fb_password  "$user" "$pass" ;;
    esac
    pass=""
}
