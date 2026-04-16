#!/bin/bash
###############################################################################
#  modules/60-certbot.sh — Certbot with nginx plugin
#
#  Installs certbot and python3-certbot-nginx.
#  Does NOT auto-run certificate issuance — user runs certbot manually.
###############################################################################

module_certbot_describe() {
    echo "Certbot — Let's Encrypt client"
}

module_certbot_check() {
    return 1
}

module_certbot_install() {
    # TODO: migrate from server-setup.sh install_certbot()
    return 0
}
