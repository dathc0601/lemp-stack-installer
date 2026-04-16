#!/bin/bash
###############################################################################
#  modules/30-mariadb.sh — MariaDB server
#
#  Installs MariaDB from official repo, secures root, tunes config.
#  Checks existing password before clobbering.
#
#  Depends on: lib/core.sh (logging, constants, command_exists, MYSQL_ROOT_PASS)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_mariadb_describe() {
    echo "MariaDB — secured, tuned"
}

module_mariadb_check() {
    command_exists mariadb && state_is_installed "mariadb"
}

module_mariadb_install() {
    section "Installing MariaDB ${MARIADB_SERIES}"
    _mariadb_install_packages
    systemctl enable --now mariadb
    _mariadb_secure_root
    _mariadb_tune
    log "MariaDB ready: $(mariadb --version)"
    state_mark_installed "mariadb"
}

# --- Private helpers --------------------------------------------------------

_mariadb_install_packages() {
    if ! command_exists mariadb; then
        curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp \
            | gpg --dearmor -o /usr/share/keyrings/mariadb-keyring.gpg

        echo "deb [signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://dlm.mariadb.com/repo/mariadb-server/${MARIADB_SERIES}/repo/ubuntu ${OS_CODENAME} main" \
            > /etc/apt/sources.list.d/mariadb.list

        apt_update
        apt_install mariadb-server mariadb-client
    else
        info "MariaDB already installed."
    fi
}

_mariadb_secure_root() {
    info "Securing MariaDB & setting root password..."
    if mariadb -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT 1" &>/dev/null; then
        log "MariaDB root password already matches — skipping."
        return
    fi
    if mariadb -u root -e "SELECT 1" &>/dev/null; then
        mariadb -u root <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL
        log "MariaDB root password set."
    else
        err "Could not connect to MariaDB. Manual intervention needed."
    fi
}

_mariadb_tune() {
    info "Tuning MariaDB..."
    local cnf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    [[ -f "$cnf" ]] || { warn "MariaDB config not found at $cnf — skipping tuning."; return; }

    # Helper: set or insert a key=value under [mysqld]
    _mariadb_set_or_add() {
        local key="$1" val="$2"
        if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$cnf"; then
            sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|" "$cnf"
        else
            sed -i "/^\[mysqld\]/a ${key} = ${val}" "$cnf"
        fi
    }

    _mariadb_set_or_add "max_allowed_packet"       "512M"
    _mariadb_set_or_add "wait_timeout"             "600"
    _mariadb_set_or_add "interactive_timeout"      "600"
    _mariadb_set_or_add "innodb_buffer_pool_size"  "512M"

    systemctl restart mariadb
    log "MariaDB tuned."
}
