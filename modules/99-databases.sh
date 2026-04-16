#!/bin/bash
###############################################################################
#  modules/99-databases.sh — Per-domain MariaDB database and user creation
#
#  Creates one database + user per configured domain.
#  Checks before creation — never clobbers existing DBs with new passwords.
#
#  Depends on: lib/core.sh (logging, constants, MYSQL_ROOT_PASS, DOMAINS)
#              lib/utils.sh (generate_password)
#              lib/credentials.sh (cred_write)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_databases_describe() {
    echo "Per-domain databases — MariaDB"
}

module_databases_check() {
    state_is_installed "databases"
}

module_databases_install() {
    section "Creating databases"

    cred_write ""
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  DOMAIN DATABASES"
    cred_write "═══════════════════════════════════════════════════════════"

    for domain in "${DOMAINS[@]}"; do
        _databases_create_for_domain "$domain"
    done

    state_mark_installed "databases"
}

# --- Private helpers --------------------------------------------------------

_databases_create_for_domain() {
    local domain="$1"
    local db_name db_user db_pass exists
    db_name=$(echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g')
    db_user="${db_name}_user"

    # Idempotency: if DB already exists, skip generating a new password
    exists=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${db_name}';" 2>/dev/null || echo "0")

    if [[ "$exists" == "1" ]]; then
        warn "Database '${db_name}' already exists — leaving it untouched."
        cred_write ""
        cred_write "[${domain}]"
        cred_write "  Web root  : ${WEB_ROOT_BASE}/${domain}"
        cred_write "  Database  : ${db_name} (pre-existing — password unchanged)"
        cred_write "  DB user   : ${db_user}"
        return
    fi

    db_pass=$(generate_password 24)
    mariadb -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL
CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOSQL

    log "DB created: ${db_name} (user: ${db_user})"
    cred_write ""
    cred_write "[${domain}]"
    cred_write "  Web root  : ${WEB_ROOT_BASE}/${domain}"
    cred_write "  Database  : ${db_name}"
    cred_write "  DB user   : ${db_user}"
    cred_write "  DB pass   : ${db_pass}"
}
