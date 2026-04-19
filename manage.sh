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

# =============================================================================
#  DATABASE HELPERS (used by manage/db-*.sh commands)
# =============================================================================

# Validate a MariaDB identifier — alphanumeric + underscore, 1-64 chars.
# Guards against SQL injection since names are interpolated into queries.
_validate_db_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_]{1,64}$ ]]
}

# Return 0 if the schema exists, 1 otherwise. Requires MYSQL_ROOT_PASS.
_db_exists() {
    local name="$1" count
    count=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${name}';" \
        2>/dev/null || echo "0")
    [[ "$count" == "1" ]]
}

# Print user-schema names (system DBs filtered out), one per line.
_list_user_databases() {
    mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA
         WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')
         ORDER BY SCHEMA_NAME;" 2>/dev/null || true
}

# Find the credentials-file block that owns a given DB name.
# Echoes the full header (e.g. "[db:mydb]" or "[example.com]") or nothing.
# Scans blocks for a "Database : NAME" line, where NAME may have a trailing
# " (…)" annotation from the idempotent install path.
_find_db_owner() {
    local db_name="$1"
    [[ -f "$CREDENTIALS_FILE" ]] || return 0
    awk -v target="$db_name" '
        /^\[.*\]$/ { block=$0; next }
        {
            # Line shape: "  Database  : value [ (annotation)]"
            if (match($0, /^[ \t]+Database[ \t]*:[ \t]*/)) {
                v = substr($0, RSTART + RLENGTH)
                sub(/[ \t]+\(.*\)$/, "", v)
                sub(/[ \t]+$/, "", v)
                if (v == target) {
                    print block
                    exit
                }
            }
        }
    ' "$CREDENTIALS_FILE" 2>/dev/null || true
}

# Remove a credentials block identified by its header line (e.g. "[db:mydb]").
# Also drops the single blank line immediately preceding the header, if any,
# so repeated add/remove cycles don't accumulate blank gaps.
# Atomic: writes tempfile, mv, re-applies mode 600.
_remove_cred_block() {
    local header="$1"
    [[ -f "$CREDENTIALS_FILE" ]] || return 0
    local tmp
    tmp=$(mktemp)
    awk -v hdr="$header" '
        BEGIN { held_blank=0; in_block=0 }
        {
            if (in_block) {
                if ($0 ~ /^\[/ || $0 ~ /^═+$/) {
                    in_block=0
                    # Fall through to non-block handling for this line
                } else {
                    next
                }
            }
            if ($0 == hdr) {
                in_block=1
                held_blank=0   # drop the blank line we were holding
                next
            }
            if ($0 == "") {
                if (held_blank) print ""
                held_blank=1
                next
            }
            if (held_blank) { print ""; held_blank=0 }
            print
        }
        END { if (held_blank) print "" }
    ' "$CREDENTIALS_FILE" > "$tmp"
    mv "$tmp" "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
}

# Update a single field within a credentials block.
# Usage: _update_cred_field "[db:mydb]" "DB pass" "newvalue"
# Preserves the original indent and field-name alignment on the line.
_update_cred_field() {
    local header="$1" field="$2" value="$3"
    [[ -f "$CREDENTIALS_FILE" ]] || return 1
    local tmp
    tmp=$(mktemp)
    awk -v hdr="$header" -v fld="$field" -v val="$value" '
        BEGIN { in_block=0 }
        $0 == hdr { in_block=1; print; next }
        in_block && /^\[/ { in_block=0 }
        in_block && /^═+$/ { in_block=0 }
        {
            if (in_block) {
                pat = "^[ \t]+" fld "[ \t]*:[ \t]*"
                if (match($0, pat)) {
                    printf "%s%s\n", substr($0, 1, RLENGTH), val
                    next
                }
            }
            print
        }
    ' "$CREDENTIALS_FILE" > "$tmp"
    mv "$tmp" "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
}

# Prompt for a password. Empty input → auto-generate 24 chars; typed input
# requires min 12 chars + a second confirm-prompt. Writes the result into the
# nameref variable.
#   Usage: _prompt_password_or_generate out_var "New"
_prompt_password_or_generate() {
    local -n _out_ref="$1"
    local label="${2:-New}"
    local pass1 pass2
    while true; do
        read -rsp "  ${label} password (empty = generate 24-char): " pass1; echo ""
        if [[ -z "$pass1" ]]; then
            _out_ref=$(generate_password 24)
            info "Generated password — will be saved to ${CREDENTIALS_FILE}."
            return 0
        fi
        if [[ ${#pass1} -lt 12 ]]; then
            warn "Password too short (${#pass1} chars; minimum 12). Try again."
            continue
        fi
        read -rsp "  Confirm                                    : " pass2; echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            warn "Passwords don't match. Try again."
            continue
        fi
        _out_ref="$pass1"
        pass1=""; pass2=""
        return 0
    done
}

# =============================================================================
#  SWAP HELPERS (shared by cmd_swap_view / cmd_swap_add / cmd_swap_remove)
# =============================================================================

# Check whether /etc/fstab has a non-commented swap entry for $1.
# The path must start the line (possibly after leading whitespace) — matches
# the real fstab format where <device> is always column 1.
_swap_fstab_has() {
    local path="$1"
    [[ -f /etc/fstab ]] || return 1
    grep -qE "^[[:space:]]*${path}[[:space:]]+none[[:space:]]+swap[[:space:]]" /etc/fstab
}

# Strip any non-commented swap entry for $1 from /etc/fstab. Atomic rewrite
# via mktemp + mv; mode mirrored from the original. Caller supplies a literal
# path; we quote dots defensively in case someone adopts `/var/swap.1` later.
_swap_fstab_remove() {
    local path="$1"
    [[ -f /etc/fstab ]] || return 0
    local tmp
    tmp=$(mktemp)
    awk -v p="$path" '
        function esc(s,   r) { r=s; gsub(/\./, "\\.", r); return r }
        BEGIN {
            pat = "^[[:space:]]*" esc(p) "[[:space:]]+none[[:space:]]+swap[[:space:]]"
        }
        $0 ~ pat { next }
        { print }
    ' /etc/fstab > "$tmp"
    chmod --reference=/etc/fstab "$tmp" 2>/dev/null || chmod 644 "$tmp"
    mv "$tmp" /etc/fstab
}

# Emit one-line swap summary for the TUI status header. Degrades gracefully
# (never err-exits, never writes state). Reads `swapon --show` output.
#   Examples:
#     "none configured"
#     "/swapfile (2.0G file, 167M used, prio -2) — active"
#     "/swapfile (2.0G file, inactive)"
#     "/swapfile (2.0G file) + 1 other — active"
#     "2 swap(s) active (not /swapfile)"
_swap_summary() {
    local active_lines self_line other_count active_count
    active_lines=$(swapon --show --noheadings 2>/dev/null || true)

    if [[ -z "$active_lines" ]]; then
        if [[ -e /swapfile ]]; then
            local size
            size=$(du -h /swapfile 2>/dev/null | awk '{print $1}' || echo "?")
            echo "/swapfile (${size} file, inactive)"
        else
            echo "none configured"
        fi
        return 0
    fi

    # swapon --show --noheadings columns: NAME TYPE SIZE USED PRIO
    self_line=$(echo "$active_lines"  | awk '$1=="/swapfile"' | head -1 || true)
    other_count=$(echo "$active_lines" | awk '$1!="/swapfile"' | wc -l | tr -d ' ' || echo 0)

    if [[ -n "$self_line" ]]; then
        local size used prio
        size=$(echo "$self_line" | awk '{print $3}')
        used=$(echo "$self_line" | awk '{print $4}')
        prio=$(echo "$self_line" | awk '{print $5}')
        if [[ "$other_count" -gt 0 ]]; then
            echo "/swapfile (${size} file) + ${other_count} other — active"
        else
            echo "/swapfile (${size} file, ${used} used, prio ${prio}) — active"
        fi
    else
        active_count=$(echo "$active_lines" | wc -l | tr -d ' ' || echo 0)
        echo "${active_count} swap(s) active (not /swapfile)"
    fi
}

# =============================================================================
#  PHP HELPERS (shared by cmd_php_config / cmd_php_pool / cmd_php_version)
# =============================================================================

# Resolve the currently active PHP version. $PHP_VERSION is already populated
# from STATE_FILE by lib/core.sh, so this is a thin accessor — the explicit
# helper keeps callers readable and gives us one point to extend later.
_php_active_version() { echo "${PHP_VERSION}"; }

# Return the systemd unit name for the active FPM (e.g. "php8.4-fpm").
_php_fpm_service() { echo "php$(_php_active_version)-fpm"; }

# Path to the active version's php.ini for a given SAPI (fpm|cli).
_php_ini_file() { echo "/etc/php/$(_php_active_version)/$1/php.ini"; }

# Path to the shared FPM pool config (www.conf).
_php_pool_file() { echo "/etc/php/$(_php_active_version)/fpm/pool.d/www.conf"; }

# Read a directive value from an ini file. Matches active (uncommented) form
# only; tolerates leading whitespace and whitespace around the `=`. Emits the
# raw value (no quotes stripped — ini values here are scalar).
#   Usage: val=$(_php_ini_get "$file" "memory_limit")
_php_ini_get() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null \
        | tail -1 | awk -F= '{sub(/^[[:space:]]*/,"",$2); sub(/[[:space:]]*$/,"",$2); print $2}' \
        || true
}

# Idempotent setter. Three cases:
#   1) active line `key = ...`     → sed replace
#   2) commented  `;key = ...`     → uncomment + set (same sed flavor as
#                                    modules/40-php.sh:82 for max_input_vars)
#   3) missing                     → append `key = value` at file end
# Dots in the key are literal (escaped) so `opcache.enable` etc. work.
_php_ini_set() {
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || err "ini file not found: ${file}"
    local esc_key
    esc_key=$(printf '%s' "$key" | sed 's/[.[\*^$/]/\\&/g')

    if grep -qE "^[[:space:]]*${esc_key}[[:space:]]*=" "$file"; then
        sed -i "s|^[[:space:]]*${esc_key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    elif grep -qE "^[[:space:]]*;[[:space:]]*${esc_key}[[:space:]]*=" "$file"; then
        sed -i "s|^[[:space:]]*;[[:space:]]*${esc_key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    else
        echo "${key} = ${value}" >> "$file"
    fi
}

# Pool directive get/set — thin wrappers around _php_ini_get/_php_ini_set
# that always target the active version's www.conf.
_php_pool_get() { _php_ini_get "$(_php_pool_file)" "$1"; }
_php_pool_set() { _php_ini_set "$(_php_pool_file)" "$1" "$2"; }

# Atomic key=value writer for STATE_FILE. Same mktemp+mv pattern as
# _swap_fstab_remove. If the file doesn't exist, creates it with mode 600.
_php_state_set() {
    local key="$1" value="$2"
    [[ -n "$key" ]] || err "_php_state_set: empty key"
    if [[ ! -f "$STATE_FILE" ]]; then
        mkdir -p "$STATE_DIR"
        : > "$STATE_FILE"
        chmod 600 "$STATE_FILE"
    fi
    local tmp
    tmp=$(mktemp)
    awk -v k="$key" -v v="$value" '
        BEGIN { written=0 }
        {
            if ($0 ~ "^" k "=") { print k "=" v; written=1; next }
            print
        }
        END { if (!written) print k "=" v }
    ' "$STATE_FILE" > "$tmp"
    chmod --reference="$STATE_FILE" "$tmp" 2>/dev/null || chmod 600 "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# List PHP minor versions with a config dir under /etc/php, sorted. One per
# line (e.g. "8.3\n8.4"). Empty output if none installed.
_php_installed_versions() {
    ls -1 /etc/php/ 2>/dev/null | grep -E '^[0-9]+\.[0-9]+$' | sort -V || true
}

# Emit the 3-line status header used above the PHP sub-menu options. Every
# read is soft-failed so an unreadable php.ini or down FPM degrades to
# "unknown"/"(unreadable)" rather than err-exit. Same pattern as
# _menu_swap_status / _menu_databases_status.
_php_summary() {
    local active other_list other fpm_state
    active=$(_php_active_version)

    # Installed versions line — mark active, list others
    other_list=""
    while IFS= read -r v; do
        [[ -z "$v" || "$v" == "$active" ]] && continue
        other_list+="${v}, "
    done < <(_php_installed_versions)
    other="${other_list%, }"

    # Active PHP release — prefer the version-specific binary (php8.1, php8.4…)
    # so we report the active FPM's release even when /usr/bin/php is still
    # pointing at an older update-alternatives default. Fall back to bare `php`
    # only if the version-specific binary isn't installed for some reason.
    local active_release
    active_release=$(php"${active}" -r 'echo PHP_VERSION;' 2>/dev/null || true)
    if [[ -z "$active_release" ]]; then
        active_release=$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo "unknown")
    fi

    # FPM service state
    if systemctl is-active --quiet "$(_php_fpm_service)" 2>/dev/null; then
        fpm_state="active"
    else
        fpm_state="inactive"
    fi

    if [[ -n "$other" ]]; then
        echo "  PHP: ${active_release} (active), ${other} (installed) — $(_php_fpm_service): ${fpm_state}"
    else
        echo "  PHP: ${active_release} (active) — $(_php_fpm_service): ${fpm_state}"
    fi

    # php.ini snapshot
    local ini mem up_ exec_ tz
    ini=$(_php_ini_file fpm)
    if [[ -f "$ini" ]]; then
        mem=$(_php_ini_get "$ini" memory_limit)
        up_=$(_php_ini_get "$ini" upload_max_filesize)
        exec_=$(_php_ini_get "$ini" max_execution_time)
        tz=$(_php_ini_get "$ini" date.timezone)
        echo "  php.ini: memory_limit=${mem:-?}, upload=${up_:-?}, exec=${exec_:-?}, tz=${tz:-?}"
    else
        echo "  php.ini: (unreadable)"
    fi

    # Pool snapshot
    local pool_file mode mc start mn mx
    pool_file=$(_php_pool_file)
    if [[ -f "$pool_file" ]]; then
        mode=$(_php_ini_get "$pool_file" pm)
        mc=$(_php_ini_get "$pool_file" pm.max_children)
        start=$(_php_ini_get "$pool_file" pm.start_servers)
        mn=$(_php_ini_get "$pool_file" pm.min_spare_servers)
        mx=$(_php_ini_get "$pool_file" pm.max_spare_servers)
        echo "  Pool www.conf: pm=${mode:-?}, max_children=${mc:-?}, start=${start:-?}, spare=${mn:-?}-${mx:-?}"
    else
        echo "  Pool www.conf: (unreadable)"
    fi
    echo ""
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
    echo "  Databases:"
    echo "    db-list                         List databases (size, tables, domain link)"
    echo "    db-info <name>                  Show DB details (charset, users, last export)"
    echo "    db-add [name]                   Create standalone DB + user + password"
    echo "    db-user-password [name]         Rotate password for a DB's user"
    echo "    db-remove [name]                Drop DB + its dedicated users + cred block"
    echo "    db-import <file> <name>         Load .sql/.sql.gz into existing DB"
    echo "    db-export [name]                Dump DB to /var/backups/databases/*.sql.gz"
    echo ""
    echo "  Swap:"
    echo "    swap-view                       Show swap state + kernel tunables + memory"
    echo "    swap-add [size]                 Create /swapfile (size in MB, e.g. 2048 or 2G)"
    echo "    swap-remove                     Swapoff + delete /swapfile + clean fstab"
    echo ""
    echo "  PHP:"
    echo "    php-config                      Edit common php.ini values (interactive)"
    echo "    php-pool                        Tune shared FPM pool (pm mode, workers)"
    echo "    php-version [version]           Switch active PHP version (e.g. 8.3)"
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
