#!/bin/bash
###############################################################################
#  lib/core.sh — Core constants, colors, logging, traps, FD setup
#
#  Sourced first (alphabetically) by install.sh.
#  Side effects on source: FD 3/4 setup, ERR/EXIT traps.
#  Everything else is constants, globals, and function definitions.
###############################################################################

# =============================================================================
#  CONSTANTS
# =============================================================================
readonly LOG_FILE="/var/log/server-setup.log"
readonly CREDENTIALS_FILE="/root/.server-credentials"
readonly STATE_DIR="/var/lib/server-setup"
readonly STATE_FILE="${STATE_DIR}/state"

readonly WEB_ROOT_BASE="/var/www"
# PHP_VERSION is NOT readonly — manage/php-version.sh switches the active
# version post-install by writing php_active_version=X.Y to STATE_FILE, and
# this block picks it up on every source of core.sh so render_template and
# cache-*.sh see the current version, not the install-time default.
PHP_VERSION="8.4"
if [[ -f "${STATE_FILE}" ]]; then
    _sv=$(awk -F= '$1=="php_active_version"{print $2; exit}' "${STATE_FILE}" 2>/dev/null || true)
    [[ -n "$_sv" ]] && PHP_VERSION="$_sv"
    unset _sv
fi
readonly NODE_MAJOR="22"
readonly MARIADB_SERIES="11.4"

# PHP tuning
readonly PHP_UPLOAD_MAX="256M"
readonly PHP_POST_MAX="256M"
readonly PHP_MAX_EXEC_TIME="600"
readonly PHP_MAX_INPUT_TIME="600"
readonly PHP_MEMORY_LIMIT="512M"
readonly PHP_MAX_INPUT_VARS="5000"

# Nginx config paths
readonly NGINX_CONF_DIR="/etc/nginx/conf.d"
readonly NGINX_SNIPPETS_DIR="/etc/nginx/snippets-server-setup"

# File Browser
readonly FB_PORT="8085"
readonly FB_USER="admin"
readonly FB_CONFIG_DIR="/etc/filebrowser"
readonly FB_DATA_DIR="/var/lib/filebrowser"

# phpMyAdmin
readonly PMA_DIR="/usr/share/phpmyadmin"
readonly PMA_HTPASSWD_FILE="/etc/nginx/.htpasswd-pma"

# Colors
readonly C_RED='\033[0;31m'
readonly C_GRN='\033[0;32m'
readonly C_YLW='\033[1;33m'
readonly C_BLU='\033[0;34m'
readonly C_RST='\033[0m'

# =============================================================================
#  RUNTIME GLOBALS  (populated by collect_user_input / detect_environment)
# =============================================================================
MYSQL_ROOT_PASS=""
FB_PASS=""
DOMAINS=()
PMA_PATH=""           # e.g. "/pma-a3f2b1c4"  (randomized)
FB_PATH=""            # e.g. "/files-d9e8f7g6" (randomized)
PMA_BLOWFISH=""
PMA_AUTH_USER=""      # HTTP basic-auth user wrapping phpMyAdmin (defaults to "admin")
PMA_AUTH_PASS=""      # HTTP basic-auth password (24-char random at install time)
NGINX_USER=""         # auto-detected: "nginx" (nginx.org) or "www-data" (distro)
SSH_PORT=""           # auto-detected from sshd
OS_CODENAME=""        # jammy / noble

# =============================================================================
#  LOGGING
# =============================================================================
log()   { echo -e "${C_GRN}[✔]${C_RST} $*"; }
info()  { echo -e "${C_BLU}[i]${C_RST} $*"; }
warn()  { echo -e "${C_YLW}[!]${C_RST} $*"; }
# err() writes to FD 4 (real terminal stderr) so the message survives tee buffering
err()   { echo -e "${C_RED}[✘]${C_RST} $*" >&4; exit 1; }

section() {
    echo ""
    echo -e "${C_BLU}═══════════════════════════════════════════════════════════${C_RST}"
    echo -e "${C_BLU}  $*${C_RST}"
    echo -e "${C_BLU}═══════════════════════════════════════════════════════════${C_RST}"
}

# =============================================================================
#  FD PRESERVATION & TRAPS
# =============================================================================
# Open FDs 3 and 4 as duplicates of the real terminal stdout/stderr.
# Critical messages (errors, ERR trap) write to FD 4 so they bypass tee
# and remain visible even if the script dies before tee can flush.
exec 3>&1 4>&2

# ERR trap writes to FD 4 (real stderr) — visible even with tee redirection
trap 'echo -e "\n${C_RED}[✘] Script failed at line $LINENO: $BASH_COMMAND${C_RST}\n${C_YLW}[i] See $LOG_FILE for full output${C_RST}" >&4' ERR

# On exit, close the tee pipe by restoring stdout/stderr, giving tee a chance to drain
trap 'exec 1>&3 2>&4' EXIT

# =============================================================================
#  CORE HELPERS
# =============================================================================
command_exists() { command -v "$1" &>/dev/null; }

# =============================================================================
#  MODULE DISPATCHER
# =============================================================================
# Runs a module by name. Calls module_<name>_check() first; if it returns 0
# (already installed), the module is skipped. Otherwise calls _install().
run_module() {
    local name="$1"
    if "module_${name}_check" 2>/dev/null; then
        info "Skipping ${name} (already installed)"
        return 0
    fi
    "module_${name}_install"
}
