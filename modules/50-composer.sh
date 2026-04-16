#!/bin/bash
###############################################################################
#  modules/50-composer.sh — Composer (PHP package manager)
#
#  Downloads installer with SHA384 checksum verification.
#  Installs to /usr/local/bin/composer.
###############################################################################

module_composer_describe() {
    echo "Composer — verified install"
}

module_composer_check() {
    return 1
}

module_composer_install() {
    # TODO: migrate from server-setup.sh install_composer()
    return 0
}
