#!/bin/bash
###############################################################################
#  modules/55-nodejs.sh — Node.js via NodeSource
#
#  Installs Node.js from NodeSource repository.
#
#  Depends on: lib/core.sh (logging, constants, command_exists)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_nodejs_describe() {
    echo "Node.js ${NODE_MAJOR} via NodeSource"
}

module_nodejs_check() {
    command_exists node && [[ "$(node -v)" == v${NODE_MAJOR}* ]] && state_is_installed "nodejs"
}

module_nodejs_install() {
    section "Installing Node.js ${NODE_MAJOR}"
    if command_exists node && [[ "$(node -v)" == v${NODE_MAJOR}* ]]; then
        info "Node.js ${NODE_MAJOR} already installed: $(node -v)"
    else
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
        apt_install nodejs
    fi
    log "Node.js installed: $(node -v) | npm: $(npm -v)"
    state_mark_installed "nodejs"
}
