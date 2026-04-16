#!/bin/bash
###############################################################################
#  modules/99-databases.sh — Per-domain MariaDB database and user creation
#
#  Creates one database + user per configured domain.
#  Checks before creation — never clobbers existing DBs with new passwords.
###############################################################################

module_databases_describe() {
    echo "Per-domain databases — MariaDB"
}

module_databases_check() {
    return 1
}

module_databases_install() {
    # TODO: migrate from server-setup.sh create_databases()
    return 0
}
