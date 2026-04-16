#!/bin/bash
###############################################################################
#  modules/80-fail2ban.sh — fail2ban intrusion prevention (NEW)
#
#  Installs fail2ban and configures jails for SSH and nginx.
#  Protects against brute-force attacks on SSH and web login endpoints.
#
#  Depends on: lib/core.sh (logging, command_exists, SSH_PORT)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_fail2ban_describe() {
    echo "fail2ban — intrusion prevention"
}

module_fail2ban_check() {
    command_exists fail2ban-server && state_is_installed "fail2ban"
}

module_fail2ban_install() {
    section "Installing fail2ban"
    apt_install fail2ban
    _fail2ban_configure_jails
    systemctl enable --now fail2ban
    log "fail2ban installed and configured."
    state_mark_installed "fail2ban"
}

# --- Private helpers --------------------------------------------------------

_fail2ban_configure_jails() {
    # Use jail.local to override defaults — jail.conf should not be edited
    cat > /etc/fail2ban/jail.local <<JAILEOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = ${SSH_PORT}
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
JAILEOF

    log "fail2ban jails configured: sshd (port ${SSH_PORT}), nginx-http-auth, nginx-botsearch"
}
