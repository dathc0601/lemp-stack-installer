#!/bin/bash
###############################################################################
#  modules/80-fail2ban.sh — fail2ban intrusion prevention (NEW)
#
#  Installs fail2ban and configures jails for SSH and nginx.
#  This is a new module not present in v2.0.1.
###############################################################################

module_fail2ban_describe() {
    echo "fail2ban — intrusion prevention"
}

module_fail2ban_check() {
    return 1
}

module_fail2ban_install() {
    # TODO: implement — new module
    return 0
}
