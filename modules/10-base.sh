#!/bin/bash
###############################################################################
#  modules/10-base.sh — Base system packages
#
#  Installs: software-properties-common, apt-transport-https, ca-certificates,
#            curl, wget, gnupg, lsb-release, unzip, git, ufw, openssl
#
#  Depends on: lib/core.sh (logging, apt wrappers)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_base_describe() {
    echo "Base system packages"
}

module_base_check() {
    # Base packages are a prerequisite for everything — re-running is cheap
    # and ensures nothing got removed. Only skip if state says we ran once.
    state_is_installed "base"
}

module_base_install() {
    section "Installing base packages"
    apt_update
    apt_upgrade
    apt_install \
        software-properties-common apt-transport-https ca-certificates \
        curl wget gnupg lsb-release unzip git ufw openssl
    log "Base packages installed."
    state_mark_installed "base"
}
