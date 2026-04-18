#!/bin/bash
###############################################################################
#  LEMP Stack Manager — Day-2 operations
#  Usage: lemp-manage <command> [args]
#
#  Commands:
#   status          Show server status (services, disk, memory, SSL, modules)
#   list-sites      List all configured domains
#   add-domain      Add a new domain with vhost, web root, and database
#   remove-domain   Remove a domain (optionally delete DB + files)
#   backup          Backup web roots and databases
#   restore         Restore from a backup
#   wp-install      Install WordPress on a domain
#
#  Dispatches to manage/<command>.sh. Shares lib/ with install.sh.
###############################################################################

set -Eeuo pipefail

# Resolve the directory this script lives in, following symlinks.
# Invoked via /usr/local/bin/lemp or /usr/local/bin/lemp-manage, both of
# which symlink to /opt/server-setup/manage.sh — we need to follow the
# symlink so relative paths (manage/*.sh, lib/*.sh) resolve under the
# real install dir, not /usr/local/bin.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
readonly SCRIPT_DIR

# --- Source library files (alphabetical: core.sh loads first) ---
for _lib in "${SCRIPT_DIR}"/lib/*.sh; do
    [[ -f "$_lib" ]] || continue
    # shellcheck source=/dev/null
    source "$_lib"
done
unset _lib

# --- Source module files (for reusing _domains_create_vhost, etc.) ---
for _mod in "${SCRIPT_DIR}"/modules/*.sh; do
    [[ -f "$_mod" ]] || continue
    # shellcheck source=/dev/null
    source "$_mod"
done
unset _mod

# =============================================================================
#  MANAGE-SPECIFIC HELPERS
# =============================================================================

# Read the MariaDB root password from the credentials file into MYSQL_ROOT_PASS.
_read_mysql_root_pass() {
    [[ -f "$CREDENTIALS_FILE" ]] || err "Credentials file not found: ${CREDENTIALS_FILE}. Run the installer first."
    MYSQL_ROOT_PASS=$(grep -E '^\s+Root pass\s*:' "$CREDENTIALS_FILE" | awk -F': ' '{print $2}' | tr -d ' ' || true)
    [[ -n "$MYSQL_ROOT_PASS" ]] || err "Cannot read MariaDB root password from ${CREDENTIALS_FILE}."

    if ! mariadb -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT 1" &>/dev/null; then
        err "MariaDB root password from credentials file is invalid. Was it changed manually?"
    fi
}

# Detect the nginx user from nginx.conf → set NGINX_USER.
_detect_nginx_user() {
    NGINX_USER=$(grep -oP '^\s*user\s+\K\S+' /etc/nginx/nginx.conf 2>/dev/null | tr -d ';' || true)
    NGINX_USER="${NGINX_USER:-www-data}"
}

# Validate a domain name format.
_validate_domain_format() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]
}

# Check if a domain vhost already exists.
_domain_exists() {
    local domain="$1"
    [[ -f "${NGINX_CONF_DIR}/${domain}.conf" ]]
}

# Convert domain to database-safe name.
_domain_db_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}

# Read a domain's DB password from the credentials file.
_read_domain_db_pass() {
    local domain="$1"
    awk -v block="[${domain}]" '
        $0 == block { found=1; next }
        found && /^\[/ { exit }
        found && /DB pass/ { sub(/.*: /, ""); print; exit }
    ' "$CREDENTIALS_FILE" || true
}

# Print usage and available commands.
_usage() {
    echo ""
    echo "  LEMP Stack Manager"
    echo ""
    echo "  Usage: lemp-manage <command> [args]"
    echo ""
    echo "  Sites:"
    echo "    status                       Show server status"
    echo "    list-sites                   List configured domains"
    echo "    add-domain <domain>          Add a new domain"
    echo "    remove-domain <domain>       Remove a domain"
    echo "    backup [domain]              Backup web roots and databases"
    echo "    restore <path> <domain>      Restore from backup"
    echo "    wp-install <domain>          Install WordPress"
    echo ""
    echo "  SSL:"
    echo "    ssl-list                     List SSL certificates + expiry"
    echo "    ssl-issue <domain>           Issue Let's Encrypt cert"
    echo "    ssl-remove <domain>          Delete Let's Encrypt cert"
    echo "    ssl-renew [domain]           Renew a cert (or all if omitted)"
    echo ""
    echo "  SSH/SFTP:"
    echo "    ssh-port [port]              Change SSH port (two-phase safety gate)"
    echo "    ssh-root-password            Change root account password"
    echo "    sftp-user-password [user]    Change a Linux user's password"
    echo "    fail2ban-maxretry [N]        Set fail2ban [DEFAULT] maxretry (1-20)"
    echo ""
    echo "  Admin apps (phpMyAdmin + File Browser):"
    echo "    appadmin-list                List admin users for both apps"
    echo "    appadmin-add [pma|fb] [user] Add an admin user"
    echo "    appadmin-password [pma|fb] [user]"
    echo "                                 Change an admin user's password"
    echo "    appadmin-remove [pma|fb] [user]"
    echo "                                 Remove an admin user"
    echo "    appadmin-paths               Rotate /pma-<hex> and /files-<hex>"
    echo "    appadmin-maxretry [N]        Set [nginx-http-auth] maxretry (1-20)"
    echo ""
    echo "  Cache (Redis, Memcached, OPcache):"
    echo "    cache-redis-toggle [on|off]     Toggle or set Redis service state"
    echo "    cache-memcached-toggle [on|off] Toggle or set Memcached service state"
    echo "    cache-opcache-toggle [on|off]   Toggle or set OPcache (edits php.ini)"
    echo "    cache-opcache-reset             Flush compiled bytecode (reloads php-fpm)"
    echo "    cache-clear                     Flush Redis + Memcached + reset OPcache"
    echo ""
}

# =============================================================================
#  DISPATCHER
# =============================================================================

# Root check
[[ $EUID -eq 0 ]] || err "lemp-manage must be run as root (use sudo)."

# No args → launch the interactive menu (`lemp` entry point).
# With args → fall through to the dispatcher below.
if [[ $# -eq 0 ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/manage/_menu.sh"
    show_menu
    exit 0
fi

# Command argument
CMD="${1:-}"
if [[ -z "$CMD" ]]; then
    _usage
    exit 1
fi
shift

# Map command name to function name (hyphens → underscores)
CMD_FUNC="cmd_${CMD//-/_}"
CMD_FILE="${SCRIPT_DIR}/manage/${CMD}.sh"

if [[ ! -f "$CMD_FILE" ]]; then
    warn "Unknown command: ${CMD}"
    _usage
    exit 1
fi

# Source the subcommand file and call its function
# shellcheck source=/dev/null
source "$CMD_FILE"

if ! declare -f "$CMD_FUNC" &>/dev/null; then
    err "Command file '${CMD}.sh' does not define '${CMD_FUNC}()'."
fi

"$CMD_FUNC" "$@"
