#!/bin/bash
###############################################################################
#  modules/25-firewall.sh — UFW firewall configuration
#
#  Allows only: detected SSH port + 80 (HTTP) + 443 (HTTPS).
#  Denies all other incoming traffic.
###############################################################################

module_firewall_describe() {
    echo "UFW firewall — SSH + HTTP + HTTPS only"
}

module_firewall_check() {
    return 1
}

module_firewall_install() {
    # TODO: migrate from server-setup.sh configure_firewall()
    return 0
}
