#!/bin/bash
###############################################################################
#  modules/55-nodejs.sh — Node.js via NodeSource
#
#  Installs Node.js LTS from NodeSource repository.
###############################################################################

module_nodejs_describe() {
    echo "Node.js via NodeSource"
}

module_nodejs_check() {
    return 1
}

module_nodejs_install() {
    # TODO: migrate from server-setup.sh install_nodejs()
    return 0
}
