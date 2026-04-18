#!/bin/bash
###############################################################################
#  manage/db-import.sh — Load a .sql / .sql.gz dump into an existing database
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-import <file> <db_name>
#
#  Requires the target DB to already exist (no silent create — force db-add
#  first so credentials get recorded). Warns loudly if the target is
#  non-empty, since dumps with DROP TABLE can silently wipe live data.
###############################################################################

cmd_db_import() {
    local file="${1:-}"
    local db_name="${2:-}"

    section "Import database"

    _read_mysql_root_pass

    # --- Source file ----------------------------------------------------------
    if [[ -z "$file" ]]; then
        read -rp "─// Path to .sql or .sql.gz file: " file || { info "Aborted."; return 0; }
    fi
    [[ -n "$file" ]] || err "Empty file path."
    [[ -f "$file" && -r "$file" ]] || err "File not found or not readable: ${file}"
    case "$file" in
        *.sql|*.sql.gz) ;;
        *) err "Unsupported extension. Expected .sql or .sql.gz." ;;
    esac

    # --- Target DB ------------------------------------------------------------
    if [[ -z "$db_name" ]]; then
        if declare -f _menu_pick_database >/dev/null; then
            db_name=$(_menu_pick_database "all") || { info "Aborted."; return 0; }
        else
            read -rp "─// Target database: " db_name || { info "Aborted."; return 0; }
        fi
    fi
    [[ -n "$db_name" ]] || err "Empty database name."
    _validate_db_name "$db_name" \
        || err "Invalid name '${db_name}': only [a-zA-Z0-9_] allowed, max 64 chars."
    _db_exists "$db_name" \
        || err "Database '${db_name}' does not exist. Create it first with: lemp-manage db-add ${db_name}"

    # --- Check if target has data already -------------------------------------
    local existing_tables existing_size
    existing_tables=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COUNT(*) FROM information_schema.TABLES WHERE table_schema='${db_name}';" 2>/dev/null || echo "0")
    existing_size=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COALESCE(ROUND(SUM(data_length + index_length)/1024/1024, 2), 0) FROM information_schema.TABLES WHERE table_schema='${db_name}';" 2>/dev/null || echo "0")

    if [[ "$existing_tables" != "0" ]]; then
        warn "Target '${db_name}' already contains ${existing_tables} table(s), ${existing_size} MB of data."
        warn "Importing may DROP and REPLACE existing tables if the dump contains DROP statements."
        confirm "Continue?" "N" || { info "Aborted."; return 0; }
    fi

    # --- Import ---------------------------------------------------------------
    info "Importing from ${file} into '${db_name}'..."
    if [[ "$file" == *.gz ]]; then
        gunzip -c "$file" | mariadb -u root -p"${MYSQL_ROOT_PASS}" "$db_name" \
            || err "Import failed (gunzip | mariadb pipeline)."
    else
        mariadb -u root -p"${MYSQL_ROOT_PASS}" "$db_name" < "$file" \
            || err "Import failed."
    fi

    # --- Report ---------------------------------------------------------------
    local new_tables new_size
    new_tables=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COUNT(*) FROM information_schema.TABLES WHERE table_schema='${db_name}';" 2>/dev/null || echo "0")
    new_size=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COALESCE(ROUND(SUM(data_length + index_length)/1024/1024, 2), 0) FROM information_schema.TABLES WHERE table_schema='${db_name}';" 2>/dev/null || echo "0")

    log "Imported into '${db_name}': ${new_tables} table(s), ${new_size} MB."
}
