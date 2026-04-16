#!/bin/bash
###############################################################################
#  modules/25-firewall.sh — UFW firewall configuration
#
#  Allows only: detected SSH port + 80 (HTTP) + 443 (HTTPS).
#  Denies all other incoming traffic.
#
#  Depends on: lib/core.sh (logging, SSH_PORT global)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_firewall_describe() {
    echo "UFW firewall — SSH + HTTP + HTTPS only"
}

module_firewall_check() {
    state_is_installed "firewall"
}

module_firewall_install() {
    section "Configuring UFW"
    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw allow 80/tcp  comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    ufw --force enable
    log "Firewall enabled. Allowed: SSH(${SSH_PORT}), 80, 443"
    state_mark_installed "firewall"
}
