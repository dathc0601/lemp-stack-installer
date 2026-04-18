#!/bin/bash
###############################################################################
#  LEMP Stack Installer — Entry Point
#  Sources lib/ and modules/, then calls main().
#
#  Module naming convention:
#    filename  NN-foo-bar.sh  →  strip prefix  →  foo-bar
#    hyphens to underscores   →  foo_bar
#    functions: module_foo_bar_describe(), module_foo_bar_check(),
#               module_foo_bar_install()
###############################################################################

set -Eeuo pipefail

readonly INSTALLER_VERSION="2.1.0-dev"
readonly INSTALLER_NAME="LEMP Stack Installer"

# Resolve the directory this script lives in (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# --- Source library files (alphabetical: core.sh loads first) ---
for _lib in "${SCRIPT_DIR}"/lib/*.sh; do
    [[ -f "$_lib" ]] || continue
    # shellcheck source=/dev/null
    source "$_lib"
done
unset _lib

# --- Source module files (sorted by numeric prefix) ---
for _mod in "${SCRIPT_DIR}"/modules/*.sh; do
    [[ -f "$_mod" ]] || continue
    # shellcheck source=/dev/null
    source "$_mod"
done
unset _mod

# --- Main ---
main() {
    # Mirror all output to log file from this point on
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo ""
    echo "  ${INSTALLER_NAME} v${INSTALLER_VERSION}"
    echo ""

    preflight_checks
    collect_user_input
    init_credentials_file

    # --- Module installation ---
    run_module "base"
    run_module "nginx"
    run_module "firewall"
    run_module "mariadb"
    run_module "php"
    run_module "redis"
    run_module "memcached"
    run_module "composer"
    run_module "nodejs"
    run_module "certbot"
    run_module "phpmyadmin"
    run_module "filebrowser"
    run_module "fail2ban"
    run_module "unattended_upgrades"
    run_module "swap"
    run_module "domains"
    run_module "databases"

    # --- Post-install ---
    write_main_credentials
    print_summary
}

# =============================================================================
#  SUMMARY  (lives in install.sh — references all globals, not tied to a module)
# =============================================================================
print_summary() {
    section "INSTALLATION COMPLETE"

    # Helpers — safe against grep returning no matches under set -e + pipefail
    safe_version() { "$@" 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown"; }

    echo ""
    echo "Installed versions:"
    echo "  Nginx       : $(nginx -v 2>&1 | cut -d'/' -f2 || echo unknown)"
    echo "  MariaDB     : $(safe_version mariadb --version)"
    echo "  PHP         : $(safe_version php -v)"
    echo "  Composer    : $(safe_version composer --version)"
    echo "  Node.js     : $(node -v 2>/dev/null || echo unknown)"
    echo "  Redis       : $(redis-server --version 2>/dev/null | awk '{print $3}' | cut -d= -f2 || echo unknown)"
    echo "  Certbot     : $(safe_version certbot --version)"
    echo ""
    echo "Domains configured:"
    for d in "${DOMAINS[@]}"; do
        echo "  • ${d} → ${WEB_ROOT_BASE}/${d}"
    done
    echo ""
    echo -e "${C_YLW}┌─────────────────────────────────────────────────────────┐${C_RST}"
    echo -e "${C_YLW}│  All credentials saved to: ${CREDENTIALS_FILE}${C_RST}"
    echo -e "${C_YLW}│  View with:  sudo cat ${CREDENTIALS_FILE}${C_RST}"
    echo -e "${C_YLW}└─────────────────────────────────────────────────────────┘${C_RST}"
    echo ""
    echo "Security notes:"
    echo "  • phpMyAdmin and File Browser use randomized URL paths (in credentials file)"
    echo "  • Default catch-all returns 444 — admin tools only accessible via your domains"
    echo "  • UFW enabled — only SSH(${SSH_PORT}), 80, 443 are open"
    echo ""
    echo "Next step — issue SSL certificates:"
    local certbot_args=""
    for d in "${DOMAINS[@]}"; do
        certbot_args+=" -d ${d} -d www.${d}"
    done
    echo "  sudo certbot --nginx${certbot_args}"
    echo ""
    echo "Auto-renewal is handled by certbot.timer (already enabled)."
    echo ""
}

main "$@"
