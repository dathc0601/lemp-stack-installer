#!/bin/bash
###############################################################################
#  modules/70-phpmyadmin.sh — phpMyAdmin with randomized URL path
#
#  Downloads latest phpMyAdmin, configures cookie auth, generates blowfish
#  secret. URL path randomized (e.g. /pma-a3f2b1c4) for obscurity.
#  Nginx snippet created for inclusion in vhosts.
###############################################################################

module_phpmyadmin_describe() {
    echo "phpMyAdmin — randomized URL path"
}

module_phpmyadmin_check() {
    return 1
}

module_phpmyadmin_install() {
    # TODO: migrate from server-setup.sh install_phpmyadmin()
    return 0
}
