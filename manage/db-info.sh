#!/bin/bash
###############################################################################
#  manage/db-info.sh — Show detailed info for one database
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-info <db_name>
#    Shows charset, collation, size, tables, users with access, and the
#    most recent export/backup path (if any).
###############################################################################

cmd_db_info() {
    local db_name="${1:-}"

    section "Database info"

    _read_mysql_root_pass

    if [[ -z "$db_name" ]]; then
        if declare -f _menu_pick_database >/dev/null; then
            db_name=$(_menu_pick_database "all") || { info "Aborted."; return 0; }
        else
            read -rp "─// Database name: " db_name || { info "Aborted."; return 0; }
        fi
    fi
    [[ -n "$db_name" ]] || err "Empty database name."
    _validate_db_name "$db_name" \
        || err "Invalid name '${db_name}': only [a-zA-Z0-9_] allowed, max 64 chars."
    _db_exists "$db_name" || err "Database '${db_name}' does not exist."

    # --- Charset + collation --------------------------------------------------
    local charset collation
    IFS=$'\t' read -r charset collation < <(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME \
         FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${db_name}';" 2>/dev/null || true)

    # --- Size + tables --------------------------------------------------------
    local size_mb tables
    IFS=$'\t' read -r size_mb tables < <(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COALESCE(ROUND(SUM(data_length + index_length)/1024/1024, 2), 0), COUNT(*) \
         FROM information_schema.TABLES WHERE table_schema='${db_name}';" 2>/dev/null || true)

    # --- Ownership (credentials file) -----------------------------------------
    local owner link_label
    owner=$(_find_db_owner "$db_name" || true)
    if [[ -z "$owner" ]]; then
        link_label="(not tracked in credentials file)"
    elif [[ "$owner" == \[db:* ]]; then
        link_label="standalone (${owner})"
    else
        local d="${owner#\[}"; d="${d%\]}"
        link_label="linked to domain ${d}"
    fi

    # --- Users with privileges on this DB -------------------------------------
    local users
    users=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT CONCAT(User, '@', Host) FROM mysql.db WHERE Db='${db_name}';" 2>/dev/null || true)

    # --- Most recent export from this feature's directory ---------------------
    local last_export="(none)" f
    if [[ -d /var/backups/databases ]]; then
        f=$(ls -t /var/backups/databases/"${db_name}"-*.sql.gz 2>/dev/null | head -1 || true)
        [[ -n "$f" ]] && last_export="$f"
    fi

    # --- Render ---------------------------------------------------------------
    echo ""
    printf "  Name       : %s\n" "$db_name"
    printf "  Charset    : %s\n" "${charset:-unknown}"
    printf "  Collation  : %s\n" "${collation:-unknown}"
    printf "  Size       : %s MB\n" "${size_mb:-0}"
    printf "  Tables     : %s\n" "${tables:-0}"
    printf "  Ownership  : %s\n" "$link_label"
    echo ""
    echo "  Users with access:"
    if [[ -z "$users" ]]; then
        echo "    (none)"
    else
        while IFS= read -r u; do
            [[ -n "$u" ]] && echo "    - ${u}"
        done <<< "$users"
    fi
    echo ""
    printf "  Last export: %s\n" "$last_export"
}
