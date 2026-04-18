#!/bin/bash
###############################################################################
#  manage/_menu.sh — Interactive menu for `lemp`
#
#  Sourced by manage.sh when invoked with no arguments.
#  Reuses cmd_* functions from the other manage/*.sh files — no duplicated
#  business logic. Each action runs in a subshell so err()/exit in a
#  subcommand returns control to the menu instead of terminating it.
#
#  Underscore filename keeps the dispatcher from exposing this as a command.
#
#  Structure: a top-level "main" menu plus category sub-menus, all driven
#  by a shared _menu_loop helper. Adding a new sub-menu is ~30 lines:
#  write _menu_<name>_options + _menu_<name>_dispatch, add a show_<name>_menu
#  wrapper, and wire a case into _menu_main_dispatch.
###############################################################################

# =============================================================================
#  SHARED UI HELPERS
# =============================================================================

# Clear screen using tput if available, falling back to a newline block.
_menu_clear() {
    if command_exists tput && tput clear &>/dev/null; then
        tput clear
    else
        printf '\n%.0s' {1..40}
    fi
}

# Read the version from the VERSION file at the repo root.
_menu_version() {
    local version_file="${SCRIPT_DIR}/VERSION"
    if [[ -f "$version_file" ]]; then
        tr -d '[:space:]' < "$version_file" || echo "unknown"
    else
        echo "unknown"
    fi
}

# Build a one-line status summary: "Disk: X/Y GB | RAM: X/Y MB | Swap: X/Y MB"
_menu_status_line() {
    local disk ram swap
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s/%s", $3, $2}' || true)
    ram=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%s/%s MB", $3, $2}' || true)
    swap=$(free -m 2>/dev/null | awk '/^Swap:/ {printf "%s/%s MB", $3, $2}' || true)

    disk="${disk:-unknown}"
    ram="${ram:-unknown}"
    swap="${swap:-unknown}"

    echo "Status: OK | Disk: ${disk} | RAM: ${ram} | Swap: ${swap}"
}

# Print the menu header. If a breadcrumb is given, append a sub-menu title row.
_menu_header() {
    local breadcrumb="${1:-}"
    local version os_name
    version=$(_menu_version)
    os_name=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Linux}" || echo "Linux")

    echo ""
    echo -e "${C_BLU}═══════════════════════════════════════════════════════════${C_RST}"
    echo -e "${C_BLU}             LEMP Stack Manager v${version}${C_RST}"
    echo -e "${C_BLU}                ${os_name}${C_RST}"
    echo -e "${C_BLU}───────────────────────────────────────────────────────────${C_RST}"
    echo "$(_menu_status_line)"
    echo -e "${C_BLU}───────────────────────────────────────────────────────────${C_RST}"
    if [[ -n "$breadcrumb" ]]; then
        echo -e "  ${C_BLU}» ${breadcrumb}${C_RST}"
        echo -e "${C_BLU}───────────────────────────────────────────────────────────${C_RST}"
    fi
    echo ""
}

# Prompt the user for a value. Returns the trimmed input via stdout.
# Usage: val=$(_menu_prompt "Domain name: ")
_menu_prompt() {
    local prompt="$1"
    local reply=""
    # shellcheck disable=SC2162
    read -rp "$prompt" reply || return 1
    echo "$reply"
}

# Pause until the user presses Enter. Safe under set -e.
_menu_pause() {
    local _unused=""
    echo ""
    # shellcheck disable=SC2162,SC2034
    read -rp "Press Enter to return to menu..." _unused || true
}

# Present a numbered picker of configured domains, filtered by SSL state.
# Returns the selected domain name on stdout (nothing else — callers capture
# via "$(_menu_pick_domain ssl-off)"). The list, prompts, and warnings all
# go to stderr so they don't leak into the captured value.
#   Usage: domain=$(_menu_pick_domain <filter>) || return 0
#   Filters: all | ssl-on | ssl-off
_menu_pick_domain() {
    local filter="${1:-all}"
    local domains=() conf name has_ssl
    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        name=$(basename "$conf" .conf)
        [[ "$name" == "000-default" ]] && continue
        has_ssl=0
        [[ -f "/etc/letsencrypt/live/${name}/fullchain.pem" ]] && has_ssl=1
        case "$filter" in
            ssl-on)  [[ $has_ssl -eq 1 ]] || continue ;;
            ssl-off) [[ $has_ssl -eq 0 ]] || continue ;;
        esac
        domains+=("$name")
    done

    if [[ ${#domains[@]} -eq 0 ]]; then
        case "$filter" in
            ssl-on)  warn "No domains have SSL certificates." >&2 ;;
            ssl-off) warn "All configured domains already have SSL." >&2 ;;
            *)       warn "No domains configured." >&2 ;;
        esac
        return 1
    fi

    {
        echo ""
        local i=1 d
        for d in "${domains[@]}"; do
            printf "  %d) %s\n" "$i" "$d"
            i=$((i + 1))
        done
        echo ""
    } >&2

    local reply
    if ! read -rp "─// Select a domain (1-${#domains[@]}) [0=Cancel]: " reply; then
        echo "" >&2
        return 1
    fi

    [[ "$reply" == "0" ]] && return 1
    [[ "$reply" =~ ^[0-9]+$ ]] || { warn "Invalid selection: ${reply}" >&2; return 1; }
    [[ "$reply" -ge 1 && "$reply" -le ${#domains[@]} ]] \
        || { warn "Out of range: ${reply}" >&2; return 1; }

    echo "${domains[$((reply - 1))]}"
}

# Present a numbered picker of real human Linux users (UID ≥ 1000, login shell,
# excluding root). Returns the selected username on stdout (nothing else —
# callers capture via "$(_menu_pick_user)"). Stderr carries the UI.
#   Usage: user=$(_menu_pick_user) || return 0
_menu_pick_user() {
    local users=() name uid shell
    while IFS=: read -r name _ uid _ _ _ shell; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]] || continue
        [[ "$name" == "root" ]] && continue
        case "$shell" in
            /usr/sbin/nologin|/sbin/nologin|/bin/false|/usr/bin/false) continue ;;
        esac
        users+=("$name")
    done < /etc/passwd

    if [[ ${#users[@]} -eq 0 ]]; then
        warn "No human users found (UID ≥ 1000 with a login shell)." >&2
        warn "Create one first: sudo adduser <name>" >&2
        return 1
    fi

    {
        echo ""
        local i=1 u
        for u in "${users[@]}"; do
            printf "  %d) %s\n" "$i" "$u"
            i=$((i + 1))
        done
        echo ""
    } >&2

    local reply
    if ! read -rp "─// Select a user (1-${#users[@]}) [0=Cancel]: " reply; then
        echo "" >&2
        return 1
    fi

    [[ "$reply" == "0" ]] && return 1
    [[ "$reply" =~ ^[0-9]+$ ]] || { warn "Invalid selection: ${reply}" >&2; return 1; }
    [[ "$reply" -ge 1 && "$reply" -le ${#users[@]} ]] \
        || { warn "Out of range: ${reply}" >&2; return 1; }

    echo "${users[$((reply - 1))]}"
}

# Present a 2-option picker for the admin app the op applies to. Returns "pma"
# or "fb" on stdout; UI and warnings to stderr. Matches the stderr-for-UI /
# stdout-for-value contract of _menu_pick_domain.
#   Usage: app=$(_menu_pick_admin_app) || return 0
_menu_pick_admin_app() {
    {
        echo ""
        echo "  1) phpMyAdmin    (HTTP basic auth / ${PMA_HTPASSWD_FILE})"
        echo "  2) File Browser  (native user DB)"
        echo ""
    } >&2
    local reply
    if ! read -rp "─// Select app (1-2) [0=Cancel]: " reply; then
        echo "" >&2; return 1
    fi
    case "$reply" in
        1) echo "pma" ;;
        2) echo "fb"  ;;
        0) return 1 ;;
        *) warn "Invalid selection: ${reply}" >&2; return 1 ;;
    esac
}

# Picker for existing phpMyAdmin basic-auth users. Reads /etc/nginx/.htpasswd-pma.
_menu_pick_pma_user() {
    if [[ ! -f "$PMA_HTPASSWD_FILE" ]]; then
        warn "No phpMyAdmin admin users yet." >&2
        warn "Add one first: lemp-manage appadmin-add pma <user>" >&2
        return 1
    fi
    local users=() name
    while IFS=: read -r name _; do
        [[ -n "$name" ]] && users+=("$name")
    done < "$PMA_HTPASSWD_FILE"
    if [[ ${#users[@]} -eq 0 ]]; then
        warn "${PMA_HTPASSWD_FILE} exists but is empty." >&2
        return 1
    fi
    {
        echo ""
        local i=1 u
        for u in "${users[@]}"; do printf "  %d) %s\n" "$i" "$u"; i=$((i + 1)); done
        echo ""
    } >&2
    local reply
    if ! read -rp "─// Select phpMyAdmin user (1-${#users[@]}) [0=Cancel]: " reply; then
        echo "" >&2; return 1
    fi
    [[ "$reply" == "0" ]] && return 1
    [[ "$reply" =~ ^[0-9]+$ ]] || { warn "Invalid selection: ${reply}" >&2; return 1; }
    [[ "$reply" -ge 1 && "$reply" -le ${#users[@]} ]] \
        || { warn "Out of range: ${reply}" >&2; return 1; }
    echo "${users[$((reply - 1))]}"
}

# Picker for existing File Browser users. Parses `filebrowser users ls`.
_menu_pick_fb_user() {
    if ! command_exists filebrowser; then
        warn "filebrowser CLI not installed." >&2
        return 1
    fi
    local db="${FB_DATA_DIR}/filebrowser.db"
    if [[ ! -f "$db" ]]; then
        warn "File Browser database not found: ${db}" >&2
        return 1
    fi
    local users=() name
    while IFS= read -r name; do
        [[ -n "$name" ]] && users+=("$name")
    done < <(filebrowser users ls -d "$db" 2>/dev/null | awk 'NR > 1 {print $1}' || true)
    if [[ ${#users[@]} -eq 0 ]]; then
        warn "No File Browser users found." >&2
        return 1
    fi
    {
        echo ""
        local i=1 u
        for u in "${users[@]}"; do printf "  %d) %s\n" "$i" "$u"; i=$((i + 1)); done
        echo ""
    } >&2
    local reply
    if ! read -rp "─// Select File Browser user (1-${#users[@]}) [0=Cancel]: " reply; then
        echo "" >&2; return 1
    fi
    [[ "$reply" == "0" ]] && return 1
    [[ "$reply" =~ ^[0-9]+$ ]] || { warn "Invalid selection: ${reply}" >&2; return 1; }
    [[ "$reply" -ge 1 && "$reply" -le ${#users[@]} ]] \
        || { warn "Out of range: ${reply}" >&2; return 1; }
    echo "${users[$((reply - 1))]}"
}

# =============================================================================
#  GENERIC MENU LOOP
# =============================================================================
#
#  Dispatch-function return-code contract:
#    0 — normal action ran; loop should pause before redraw so the user can
#        read the output.
#    1 — exit this loop (main menu: exit program; sub-menu: back to parent).
#    2 — sub-menu just returned; skip the pause and redraw immediately, since
#        the sub-menu already drew a fresh frame on its way out.
#
#  Regressions here silently break navigation feel — keep the contract intact.
_menu_loop() {
    local breadcrumb="$1"
    local options_fn="$2"
    local dispatch_fn="$3"
    local prompt="$4"

    local choice rc
    while true; do
        _menu_clear
        _menu_header "$breadcrumb"
        "$options_fn"

        # Guard `read` under set -e: EOF (Ctrl+D) returns non-zero, which
        # would kill the loop. We want a clean return instead.
        if ! read -rp "$prompt" choice; then
            echo ""
            return 0
        fi

        # `|| rc=$?` is mandatory: under set -e, a bare call would abort
        # the loop when dispatch returns 1 or 2 (both are legitimate signals).
        rc=0
        "$dispatch_fn" "$choice" || rc=$?
        case "$rc" in
            1) return 0 ;;
            2) ;;
            *) [[ -n "$choice" ]] && _menu_pause ;;
        esac
    done
}

# =============================================================================
#  MAIN MENU
# =============================================================================

_menu_main_options() {
    echo "  1) Manage sites              (domains, backups, WordPress)"
    echo "  2) Manage SSL                (issue, renew, remove certificates)"
    echo "  3) Manage SSH/SFTP           (port, passwords, fail2ban)"
    echo "  4) Manage admin apps         (users, paths, auth retries)"
    echo "  5) Server status             (services, disk, memory, SSL)"
    echo ""
    echo "  0) Exit"
    echo ""
}

_menu_main_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            show_sites_menu
            return 2  # sub-menu already drew its own frame; skip pause
            ;;
        2)
            show_ssl_menu
            return 2
            ;;
        3)
            show_ssh_menu
            return 2
            ;;
        4)
            show_appadmin_menu
            return 2
            ;;
        5)
            ( cmd_status ) || true
            ;;
        0|q|Q|exit|quit)
            return 1
            ;;
        "")
            # Empty input — just redraw without complaining
            ;;
        *)
            warn "Invalid choice: ${choice}"
            ;;
    esac
    return 0
}

# =============================================================================
#  SITES SUB-MENU
# =============================================================================

_menu_sites_options() {
    echo "  1) List sites                (configured domains + SSL)"
    echo "  2) Add domain                (vhost + database)"
    echo "  3) Remove domain"
    echo "  4) Backup                    (all domains or one)"
    echo "  5) Restore                   (from backup path)"
    echo "  6) Install WordPress         (on a domain)"
    echo ""
    echo "  0) Back to main menu"
    echo ""
}

_menu_sites_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            ( cmd_list_sites ) || true
            ;;
        2)
            local domain
            domain=$(_menu_prompt "Domain to add (e.g. example.com): ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_add_domain "$domain" ) || true
            ;;
        3)
            local domain
            domain=$(_menu_prompt "Domain to remove: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_remove_domain "$domain" ) || true
            ;;
        4)
            local domain
            domain=$(_menu_prompt "Domain to backup (leave empty for all): ") || return 0
            ( cmd_backup "$domain" ) || true
            ;;
        5)
            local backup_path domain
            backup_path=$(_menu_prompt "Backup path (e.g. /var/backups/server-setup/2026-04-17/example.com): ") || return 0
            [[ -n "$backup_path" ]] || { warn "No backup path entered."; return 0; }
            domain=$(_menu_prompt "Target domain: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_restore "$backup_path" "$domain" ) || true
            ;;
        6)
            local domain
            domain=$(_menu_prompt "Domain for WordPress install: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_wp_install "$domain" ) || true
            ;;
        0|b|B|back)
            return 1
            ;;
        "")
            ;;
        *)
            warn "Invalid choice: ${choice}"
            ;;
    esac
    return 0
}

# =============================================================================
#  SSL SUB-MENU
# =============================================================================

_menu_ssl_options() {
    echo "  1) List SSL certificates     (domains with/without SSL, expiry)"
    echo "  2) Issue SSL                 (Let's Encrypt via certbot)"
    echo "  3) Remove SSL                (delete certificate)"
    echo "  4) Renew SSL                 (force renewal for one, or check all)"
    echo ""
    echo "  0) Back to main menu"
    echo ""
}

_menu_ssl_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            ( cmd_ssl_list ) || true
            ;;
        2)
            # Only show domains that don't yet have SSL
            local domain
            domain=$(_menu_pick_domain "ssl-off") || return 0
            ( cmd_ssl_issue "$domain" ) || true
            ;;
        3)
            # Only show domains that do have SSL
            local domain
            domain=$(_menu_pick_domain "ssl-on") || return 0
            ( cmd_ssl_remove "$domain" ) || true
            ;;
        4)
            # Renew a specific cert — pick from those with SSL
            local domain
            domain=$(_menu_pick_domain "ssl-on") || return 0
            ( cmd_ssl_renew "$domain" ) || true
            ;;
        0|b|B|back)
            return 1
            ;;
        "")
            ;;
        *)
            warn "Invalid choice: ${choice}"
            ;;
    esac
    return 0
}

# =============================================================================
#  SSH/SFTP SUB-MENU
# =============================================================================

_menu_ssh_options() {
    echo "  1) Change SSH port           (sshd drop-in + UFW + fail2ban)"
    echo "  2) Change root password      (root SSH/console login)"
    echo "  3) Change user password      (passwd for a Linux user)"
    echo "  4) fail2ban max retries      (failed logins before ban)"
    echo ""
    echo "  0) Back to main menu"
    echo ""
}

_menu_ssh_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            # cmd_ssh_port prompts interactively; no pre-selection needed.
            ( cmd_ssh_port ) || true
            ;;
        2)
            ( cmd_ssh_root_password ) || true
            ;;
        3)
            local user
            user=$(_menu_pick_user) || return 0
            ( cmd_sftp_user_password "$user" ) || true
            ;;
        4)
            ( cmd_fail2ban_maxretry ) || true
            ;;
        0|b|B|back)
            return 1
            ;;
        "")
            ;;
        *)
            warn "Invalid choice: ${choice}"
            ;;
    esac
    return 0
}

# =============================================================================
#  ADMIN APPS SUB-MENU
# =============================================================================

_menu_appadmin_options() {
    echo "  1) Change admin paths        (rotate /pma-<hex> and /files-<hex>)"
    echo "  2) List admin users          (phpMyAdmin + File Browser)"
    echo "  3) Add admin user            (pick app, username, password)"
    echo "  4) Change admin password     (pick app, user, new password)"
    echo "  5) Delete admin user         (pick app, user)"
    echo "  6) Auth login retries        (fail2ban [nginx-http-auth] maxretry)"
    echo ""
    echo "  0) Back to main menu"
    echo ""
}

_menu_appadmin_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            ( cmd_appadmin_paths ) || true
            ;;
        2)
            ( cmd_appadmin_list ) || true
            ;;
        3)
            # App + username + password are collected inside the command itself
            # (it calls _menu_pick_admin_app when app arg is missing).
            ( cmd_appadmin_add ) || true
            ;;
        4)
            ( cmd_appadmin_password ) || true
            ;;
        5)
            ( cmd_appadmin_remove ) || true
            ;;
        6)
            ( cmd_appadmin_maxretry ) || true
            ;;
        0|b|B|back)
            return 1
            ;;
        "")
            ;;
        *)
            warn "Invalid choice: ${choice}"
            ;;
    esac
    return 0
}

# =============================================================================
#  ENTRY POINTS
# =============================================================================

# Source all manage/*.sh files so cmd_* functions are available.
# Skip the underscore-prefixed files (this one) to avoid re-sourcing.
_menu_load_commands() {
    local f
    for f in "${SCRIPT_DIR}"/manage/*.sh; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == _* ]] && continue
        # shellcheck source=/dev/null
        source "$f"
    done
}

# Public entry point — called by manage.sh when invoked with no args.
show_menu() {
    _menu_load_commands
    _menu_loop "" _menu_main_options _menu_main_dispatch \
        "─// Enter your choice (0-5) [Ctrl+C=Exit]: "
    echo ""
    info "Goodbye."
}

# Sites sub-menu — invoked from _menu_main_dispatch.
# Does NOT call _menu_load_commands: show_menu already did it before we got here.
show_sites_menu() {
    _menu_loop "1. Manage sites" _menu_sites_options _menu_sites_dispatch \
        "─// Enter your choice (0-6) [0=Back]: "
}

# SSL sub-menu — invoked from _menu_main_dispatch.
show_ssl_menu() {
    _menu_loop "2. Manage SSL" _menu_ssl_options _menu_ssl_dispatch \
        "─// Enter your choice (0-4) [0=Back]: "
}

# SSH/SFTP sub-menu — invoked from _menu_main_dispatch.
show_ssh_menu() {
    _menu_loop "3. Manage SSH/SFTP" _menu_ssh_options _menu_ssh_dispatch \
        "─// Enter your choice (0-4) [0=Back]: "
}

# Admin apps sub-menu — invoked from _menu_main_dispatch.
show_appadmin_menu() {
    _menu_loop "4. Manage admin apps" _menu_appadmin_options _menu_appadmin_dispatch \
        "─// Enter your choice (0-6) [0=Back]: "
}
