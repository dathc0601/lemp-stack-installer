#!/bin/bash
###############################################################################
#  manage/db-add.sh — Create a standalone database + user + password
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-add [db_name]
#
#  Writes a `[db:${name}]` block to /root/.server-credentials. Distinct from
#  `[${domain}]` blocks so remove-domain and db-remove own non-overlapping
#  scopes.
###############################################################################

cmd_db_add() {
    local db_name="${1:-}"

    section "Add database"

    _read_mysql_root_pass

    # --- DB name --------------------------------------------------------------
    if [[ -z "$db_name" ]]; then
        while true; do
            read -rp "─// Database name: " db_name || { info "Aborted."; return 0; }
            [[ -n "$db_name" ]] || { warn "Empty name."; continue; }
            _validate_db_name "$db_name" \
                || { warn "Invalid: only [a-zA-Z0-9_] allowed, max 64 chars."; continue; }
            break
        done
    else
        _validate_db_name "$db_name" \
            || err "Invalid name '${db_name}': only [a-zA-Z0-9_] allowed, max 64 chars."
    fi

    if _db_exists "$db_name"; then
        err "Database '${db_name}' already exists. Use db-info to inspect or db-remove to drop."
    fi

    # --- DB user (default: same as DB name) -----------------------------------
    local db_user
    read -rp "─// DB user [${db_name}]: " db_user || { info "Aborted."; return 0; }
    db_user="${db_user:-$db_name}"
    _validate_db_name "$db_user" \
        || err "Invalid user '${db_user}': only [a-zA-Z0-9_] allowed, max 64 chars."

    # --- Password -------------------------------------------------------------
    local db_pass=""
    _prompt_password_or_generate db_pass "DB user"

    # --- Create DB + user + grants --------------------------------------------
    mariadb -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL || err "Failed to create database/user."
CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOSQL

    # --- Write credentials block ----------------------------------------------
    cred_write ""
    cred_write "[db:${db_name}]"
    cred_write "  Database  : ${db_name}"
    cred_write "  DB user   : ${db_user}"
    cred_write "  DB pass   : ${db_pass}"

    db_pass=""
    log "Database '${db_name}' created with user '${db_user}'. Credentials saved to ${CREDENTIALS_FILE}."
}
