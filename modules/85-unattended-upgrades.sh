#!/bin/bash
###############################################################################
#  modules/85-unattended-upgrades.sh — Automatic security updates (NEW)
#
#  Enables unattended-upgrades for automatic security patches.
#  Configures automatic removal of unused kernel packages.
#
#  Depends on: lib/core.sh (logging)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_unattended_upgrades_describe() {
    echo "Unattended upgrades — automatic security patches"
}

module_unattended_upgrades_check() {
    command_exists unattended-upgrade && state_is_installed "unattended_upgrades"
}

module_unattended_upgrades_install() {
    section "Configuring unattended upgrades"
    apt_install unattended-upgrades apt-listchanges
    _unattended_upgrades_configure
    systemctl enable --now unattended-upgrades
    log "Unattended upgrades enabled for security patches."
    state_mark_installed "unattended_upgrades"
}

# --- Private helpers --------------------------------------------------------

_unattended_upgrades_configure() {
    # Enable automatic security updates and clean up old kernels
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    # Ensure only security updates are applied (Ubuntu default, but be explicit)
    local conf="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [[ -f "$conf" ]]; then
        # Enable automatic removal of unused dependencies
        sed -i 's|^//Unattended-Upgrade::Remove-Unused-Kernel-Packages.*|Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";|' "$conf"
        sed -i 's|^//Unattended-Upgrade::Remove-Unused-Dependencies.*|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' "$conf"
    fi
}
