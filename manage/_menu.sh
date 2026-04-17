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
###############################################################################

# =============================================================================
#  PRIVATE HELPERS
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

# Print the menu header.
_menu_header() {
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
    echo ""
}

# Print the numbered option list.
_menu_options() {
    echo "  1) Server status             (services, disk, memory, SSL)"
    echo "  2) List sites                (configured domains + SSL)"
    echo "  3) Add domain                (vhost + database)"
    echo "  4) Remove domain"
    echo "  5) Backup                    (all domains or one)"
    echo "  6) Restore                   (from backup path)"
    echo "  7) Install WordPress         (on a domain)"
    echo ""
    echo "  0) Exit"
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

# =============================================================================
#  DISPATCH
# =============================================================================

# Run one menu action. Each action is wrapped in a subshell so that err()
# (which calls exit 1) terminates only the action, not the menu.
_menu_dispatch() {
    local choice="$1"
    case "$choice" in
        1)
            ( cmd_status ) || true
            ;;
        2)
            ( cmd_list_sites ) || true
            ;;
        3)
            local domain
            domain=$(_menu_prompt "Domain to add (e.g. example.com): ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_add_domain "$domain" ) || true
            ;;
        4)
            local domain
            domain=$(_menu_prompt "Domain to remove: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_remove_domain "$domain" ) || true
            ;;
        5)
            local domain
            domain=$(_menu_prompt "Domain to backup (leave empty for all): ") || return 0
            ( cmd_backup "$domain" ) || true
            ;;
        6)
            local backup_path domain
            backup_path=$(_menu_prompt "Backup path (e.g. /var/backups/server-setup/2026-04-17/example.com): ") || return 0
            [[ -n "$backup_path" ]] || { warn "No backup path entered."; return 0; }
            domain=$(_menu_prompt "Target domain: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_restore "$backup_path" "$domain" ) || true
            ;;
        7)
            local domain
            domain=$(_menu_prompt "Domain for WordPress install: ") || return 0
            [[ -n "$domain" ]] || { warn "No domain entered."; return 0; }
            ( cmd_wp_install "$domain" ) || true
            ;;
        0|q|Q|exit|quit)
            return 1  # signal main loop to break
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
#  MAIN LOOP
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

show_menu() {
    _menu_load_commands

    local choice
    while true; do
        _menu_clear
        _menu_header
        _menu_options

        # Read choice. `|| break` catches EOF (Ctrl+D) under set -e.
        if ! read -rp "─// Enter your choice (0-7) [Ctrl+C=Exit]: " choice; then
            echo ""
            break
        fi

        # Dispatch; return value 1 means "exit the loop".
        if ! _menu_dispatch "$choice"; then
            break
        fi

        # Pause between actions so output doesn't scroll away.
        # Skip the pause if the user entered nothing (just hit Enter to redraw).
        [[ -n "$choice" ]] && _menu_pause
    done

    echo ""
    info "Goodbye."
}
