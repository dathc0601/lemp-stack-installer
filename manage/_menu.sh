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
    echo "  2) Server status             (services, disk, memory, SSL)"
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
        "─// Enter your choice (0-2) [Ctrl+C=Exit]: "
    echo ""
    info "Goodbye."
}

# Sites sub-menu — invoked from _menu_main_dispatch.
# Does NOT call _menu_load_commands: show_menu already did it before we got here.
show_sites_menu() {
    _menu_loop "1. Manage sites" _menu_sites_options _menu_sites_dispatch \
        "─// Enter your choice (0-6) [0=Back]: "
}
