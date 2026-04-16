#!/bin/bash
###############################################################################
#  lib/input.sh — Interactive user prompts
#
#  Pure function definitions — no side effects on source.
#  Depends on: lib/core.sh (logging, constants, globals)
#              lib/utils.sh (generate_password, confirm)
#
#  Password rules:
#   - Empty input → auto-generate 24+ char random password
#   - Manual input → minimum 12 chars + confirmation
#   - Never echo passwords to stdout
###############################################################################

# =============================================================================
#  ORCHESTRATOR
# =============================================================================
collect_user_input() {
    section "Configuration"

    prompt_mysql_password
    prompt_filebrowser_password
    prompt_domains

    echo ""
    info "Summary:"
    echo "  MariaDB root pass : (will be saved to $CREDENTIALS_FILE)"
    echo "  File Browser pass : (will be saved to $CREDENTIALS_FILE)"
    echo "  Domains           : ${DOMAINS[*]}"
    echo ""
    confirm "Proceed with installation?" "Y" || err "Installation cancelled by user."
}

# =============================================================================
#  PASSWORD PROMPTS
# =============================================================================
prompt_mysql_password() {
    echo ""
    echo "MariaDB root password"
    echo "  • Press Enter to auto-generate a strong password (recommended)"
    echo "  • Or type your own (min 12 characters)"
    while true; do
        read -rsp "  Password: " MYSQL_ROOT_PASS; echo ""
        if [[ -z "$MYSQL_ROOT_PASS" ]]; then
            MYSQL_ROOT_PASS=$(generate_password 28)
            log "Generated MariaDB root password (will be saved to credentials file)."
            return
        fi
        if [[ ${#MYSQL_ROOT_PASS} -lt 12 ]]; then
            warn "Password too short (minimum 12 characters). Try again."
            continue
        fi
        local confirm_pass
        read -rsp "  Confirm : " confirm_pass; echo ""
        if [[ "$MYSQL_ROOT_PASS" == "$confirm_pass" ]]; then
            log "MariaDB root password set."
            return
        fi
        warn "Passwords don't match. Try again."
    done
}

prompt_filebrowser_password() {
    echo ""
    echo "File Browser admin password"
    echo "  • Press Enter to auto-generate a strong password (recommended)"
    echo "  • Or type your own (min 12 characters)"
    while true; do
        read -rsp "  Password: " FB_PASS; echo ""
        if [[ -z "$FB_PASS" ]]; then
            FB_PASS=$(generate_password 20)
            log "Generated File Browser password."
            return
        fi
        if [[ ${#FB_PASS} -lt 12 ]]; then
            warn "Password too short (minimum 12 characters). Try again."
            continue
        fi
        local confirm_pass
        read -rsp "  Confirm : " confirm_pass; echo ""
        if [[ "$FB_PASS" == "$confirm_pass" ]]; then
            log "File Browser password set."
            return
        fi
        warn "Passwords don't match. Try again."
    done
}

# =============================================================================
#  DOMAIN INPUT
# =============================================================================
prompt_domains() {
    echo ""
    echo "Domains to host (one per line, empty line to finish):"
    echo "  Example: example.com   (don't include https:// or www.)"
    while true; do
        local input
        read -rp "  Domain: " input
        if [[ -z "$input" ]]; then
            [[ ${#DOMAINS[@]} -gt 0 ]] && break
            warn "Add at least one domain."
            continue
        fi
        if ! [[ "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
            warn "Invalid domain format — skipped."
            continue
        fi
        # De-dupe
        local d found=0
        for d in "${DOMAINS[@]:-}"; do
            [[ "$d" == "$input" ]] && { found=1; break; }
        done
        [[ $found -eq 1 ]] && { warn "Already added — skipped."; continue; }
        DOMAINS+=("$input")
        log "Added: $input"
    done
}
