#!/bin/bash
###############################################################################
#  modules/60-certbot.sh — Certbot with nginx plugin
#
#  Installs certbot and python3-certbot-nginx.
#  Does NOT auto-run certificate issuance — user runs certbot manually.
#
#  Depends on: lib/core.sh (logging, command_exists)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_certbot_describe() {
    echo "Certbot — Let's Encrypt client"
}

module_certbot_check() {
    command_exists certbot && state_is_installed "certbot"
}

module_certbot_install() {
    section "Installing Certbot"
    apt_install certbot python3-certbot-nginx
    log "Certbot installed: $(certbot --version 2>&1)"
    state_mark_installed "certbot"
}
