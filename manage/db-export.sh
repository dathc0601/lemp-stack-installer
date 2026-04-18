#!/bin/bash
###############################################################################
#  manage/db-export.sh — Dump a database to /var/backups/databases/*.sql.gz
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-export <db_name>
#
#  Streams mariadb-dump | gzip (no buffering of the full dump in memory).
#  Prefers `mariadb-dump` on MariaDB 10.6+; falls back to `mysqldump`.
###############################################################################

cmd_db_export() {
    local db_name="${1:-}"

    section "Export database"

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

    # --- Destination ----------------------------------------------------------
    local dest_dir="/var/backups/databases"
    mkdir -p "$dest_dir"
    chmod 700 "$dest_dir"

    local ts out_file
    ts=$(date '+%Y-%m-%d_%H%M%S')
    out_file="${dest_dir}/${db_name}-${ts}.sql.gz"

    # --- Pick dump binary -----------------------------------------------------
    local dump_bin
    if command_exists mariadb-dump; then
        dump_bin="mariadb-dump"
    elif command_exists mysqldump; then
        dump_bin="mysqldump"
    else
        err "Neither mariadb-dump nor mysqldump is installed."
    fi

    # --- Dump -----------------------------------------------------------------
    info "Exporting '${db_name}' with ${dump_bin} → ${out_file}"
    # shellcheck disable=SC2312
    if ! "$dump_bin" -u root -p"${MYSQL_ROOT_PASS}" \
            --single-transaction --quick --lock-tables=false \
            "$db_name" 2>/dev/null | gzip > "$out_file"; then
        rm -f "$out_file"
        err "Export failed."
    fi
    chmod 600 "$out_file"

    local size
    size=$(du -h "$out_file" 2>/dev/null | awk '{print $1}' || echo "?")
    log "Exported '${db_name}' → ${out_file} (${size})."
}
