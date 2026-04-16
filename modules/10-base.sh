#!/bin/bash
###############################################################################
#  modules/10-base.sh — Base system packages
#
#  Installs: software-properties-common, apt-transport-https, ca-certificates,
#            curl, wget, gnupg, lsb-release, unzip, git, ufw, openssl
###############################################################################

module_base_describe() {
    echo "Base system packages"
}

module_base_check() {
    return 1
}

module_base_install() {
    # TODO: migrate from server-setup.sh install_base_packages()
    return 0
}
