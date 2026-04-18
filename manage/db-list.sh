#!/bin/bash
###############################################################################
#  manage/db-list.sh — List user databases with size, tables, domain link
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-list
###############################################################################

cmd_db_list() {
    section "Databases"

    _read_mysql_root_pass

    # Pull (name, size_mb, tables) for every user-schema.
    # LEFT JOIN so DBs with zero tables still appear; COALESCE on SUM handles
    # schemas where all tables are empty (SUM returns NULL for that group).
    local rows
    rows=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B <<'EOSQL' 2>/dev/null || true
SELECT
    s.SCHEMA_NAME,
    COALESCE(ROUND(SUM(t.data_length + t.index_length)/1024/1024, 2), 0) AS size_mb,
    COUNT(t.table_name) AS tables
FROM information_schema.SCHEMATA s
LEFT JOIN information_schema.TABLES t ON t.table_schema = s.SCHEMA_NAME
WHERE s.SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')
GROUP BY s.SCHEMA_NAME
ORDER BY s.SCHEMA_NAME;
EOSQL
    )

    if [[ -z "$rows" ]]; then
        info "No user databases found."
        return 0
    fi

    printf "  %-30s  %10s  %7s  %s\n" "Database" "Size" "Tables" "Linked to"
    printf "  %-30s  %10s  %7s  %s\n" "------------------------------" "----------" "-------" "-------------------------"

    local total_mb=0 count=0 name size tables owner linked
    while IFS=$'\t' read -r name size tables; do
        [[ -n "$name" ]] || continue
        count=$((count + 1))
        owner=$(_find_db_owner "$name" || true)
        if [[ -z "$owner" ]]; then
            linked="(untracked)"
        elif [[ "$owner" == \[db:* ]]; then
            linked="(standalone)"
        else
            linked="${owner#\[}"
            linked="${linked%\]}"
        fi
        printf "  %-30s  %9s MB  %7s  %s\n" "$name" "$size" "$tables" "$linked"
        # Accumulate total using awk for fractional math
        total_mb=$(awk -v a="$total_mb" -v b="$size" 'BEGIN { printf "%.2f", a + b }')
    done <<< "$rows"

    echo ""
    info "${count} database(s), ${total_mb} MB total."
}
