#!/bin/bash
###############################################################################
#  modules/30-mariadb.sh — MariaDB server
#
#  Installs MariaDB from official repo, secures root, tunes config.
#  Checks existing password before clobbering.
###############################################################################

module_mariadb_describe() {
    echo "MariaDB — secured, tuned"
}

module_mariadb_check() {
    return 1
}

module_mariadb_install() {
    # TODO: migrate from server-setup.sh install_mariadb(), configure_mariadb(), tune_mariadb()
    return 0
}
