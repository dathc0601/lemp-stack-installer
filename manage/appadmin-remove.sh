#!/bin/bash
###############################################################################
#  manage/appadmin-remove.sh — Remove an admin user
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-remove [pma|fb] [username]
#
#  Safety: refuses to remove the last PMA user while auth_basic is active
#  (would return 401 on every request). For FB, refuses to remove the last
#  admin-flagged user (same reason — would lock admins out).
###############################################################################

_appadmin_pma_user_count() {
    [[ -f "$PMA_HTPASSWD_FILE" ]] || { echo "0"; return 0; }
    awk -F: 'NF >= 2 && $1 != "" { n++ } END { print n+0 }' "$PMA_HTPASSWD_FILE"
}

_appadmin_remove_pma() {
    local user="$1"
    [[ -f "$PMA_HTPASSWD_FILE" ]] \
        || err "No htpasswd file: ${PMA_HTPASSWD_FILE}. Nothing to remove."
    grep -q "^${user}:" "$PMA_HTPASSWD_FILE" \
        || err "User '${user}' not found in ${PMA_HTPASSWD_FILE}."

    local count
    count=$(_appadmin_pma_user_count)
    if [[ "$count" -le 1 ]]; then
        err "Refusing to remove the last phpMyAdmin admin user — would lock out every request with 401. Add a replacement first: lemp-manage appadmin-add pma <new-user>."
    fi

    htpasswd -D "$PMA_HTPASSWD_FILE" "$user" >/dev/null \
        || err "htpasswd -D failed."
    log "Removed phpMyAdmin admin user '${user}'."
}

_appadmin_fb_admin_count() {
    local db="${FB_DATA_DIR}/filebrowser.db"
    command_exists filebrowser || { echo "0"; return 0; }
    [[ -f "$db" ]] || { echo "0"; return 0; }
    # Admin column is "true" / "false" — case-insensitive match, skip header.
    filebrowser users ls -d "$db" 2>/dev/null \
        | awk 'NR > 1 && tolower($2) == "true" { n++ } END { print n+0 }'
}

_appadmin_remove_fb() {
    local user="$1"
    command_exists filebrowser || err "filebrowser CLI not found."
    local db="${FB_DATA_DIR}/filebrowser.db"
    [[ -f "$db" ]] || err "File Browser database not found: ${db}"

    # Determine whether the victim is admin-flagged
    local victim_admin
    victim_admin=$(filebrowser users ls -d "$db" 2>/dev/null \
        | awk -v u="$user" 'NR > 1 && $1 == u { print tolower($2); exit }' || true)
    [[ -n "$victim_admin" ]] || err "User '${user}' not found in File Browser."

    if [[ "$victim_admin" == "true" ]]; then
        local admins
        admins=$(_appadmin_fb_admin_count)
        if [[ "$admins" -le 1 ]]; then
            err "Refusing to remove the last File Browser admin — add a replacement first: lemp-manage appadmin-add fb <new-user>."
        fi
    fi

    filebrowser users rm "$user" -d "$db" >/dev/null 2>&1 \
        || err "filebrowser users rm failed for '${user}'."
    log "Removed File Browser user '${user}'."
}

cmd_appadmin_remove() {
    local app="${1:-}" user="${2:-}"

    section "Remove admin user"

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

    confirm "Remove ${app} user '${user}'?" "N" || { info "Aborted."; return 0; }

    case "$app" in
        pma) _appadmin_remove_pma "$user" ;;
        fb)  _appadmin_remove_fb  "$user" ;;
    esac
}
