#!/bin/bash
###############################################################################
#  modules/40-php.sh — PHP 8.4 + extensions + FPM configuration
#
#  Installs from ppa:ondrej/php. Aligns FPM pool user to nginx user.
#  Tunes php.ini (upload limits, OPcache, expose_php=Off).
###############################################################################

module_php_describe() {
    echo "PHP 8.4 — FPM, extensions, tuned"
}

module_php_check() {
    return 1
}

module_php_install() {
    # TODO: migrate from server-setup.sh install_php(), configure_php_fpm(), tune_php_ini()
    return 0
}
