#!/bin/bash
###############################################################################
#  manage/appadmin-list.sh — List admin users per admin app
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-list
#
#  Prints phpMyAdmin basic-auth users (from .htpasswd-pma) and File Browser
#  users (from `filebrowser users ls`) side by side.
###############################################################################

_appadmin_list_pma() {
    echo "phpMyAdmin admin users (HTTP basic auth)"
    echo "────────────────────────────────────────"
    if [[ ! -f "$PMA_HTPASSWD_FILE" ]]; then
        echo "  (no users — run 'lemp-manage appadmin-add pma <user>' to enable auth)"
        return 0
    fi
    local count=0 user
    while IFS=: read -r user _; do
        [[ -n "$user" ]] || continue
        printf "  %s\n" "$user"
        count=$((count + 1))
    done < "$PMA_HTPASSWD_FILE"
    [[ $count -eq 0 ]] && echo "  (file exists but is empty)"
}

_appadmin_list_fb() {
    echo "File Browser users (app-level)"
    echo "──────────────────────────────"
    if ! command_exists filebrowser; then
        echo "  (filebrowser CLI not installed)"
        return 0
    fi
    local db="${FB_DATA_DIR}/filebrowser.db"
    if [[ ! -f "$db" ]]; then
        echo "  (database not found: ${db})"
        return 0
    fi
    local out
    out=$(filebrowser users ls -d "$db" 2>/dev/null || true)
    if [[ -z "$out" ]]; then
        echo "  (no users)"
        return 0
    fi
    # Indent each line for visual consistency with the PMA block
    echo "$out" | sed 's/^/  /'
}

cmd_appadmin_list() {
    section "Admin-app users"
    _appadmin_list_pma
    echo ""
    _appadmin_list_fb
}
