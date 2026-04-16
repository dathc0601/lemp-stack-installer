#!/bin/bash
###############################################################################
#  lib/preflight.sh — Pre-flight checks
#
#  Pure function definitions — no side effects on source.
#  Depends on: lib/core.sh (logging, constants, command_exists)
#              lib/utils.sh (confirm)
###############################################################################

# =============================================================================
#  PRE-FLIGHT
# =============================================================================
preflight_checks() {
    section "Pre-flight checks"

    # Root
    [[ $EUID -eq 0 ]] || err "This script must be run as root (use sudo)."
    log "Running as root"

    # OS detection
    [[ -f /etc/os-release ]] || err "Cannot detect OS — /etc/os-release not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        err "Unsupported OS: ${PRETTY_NAME:-unknown}. Only Ubuntu is supported."
    fi
    case "${VERSION_ID:-}" in
        22.04|24.04)
            OS_CODENAME="${VERSION_CODENAME}"
            log "Detected: ${PRETTY_NAME} (${OS_CODENAME})"
            ;;
        *)
            err "Unsupported Ubuntu version: ${VERSION_ID}. Supported: 22.04, 24.04."
            ;;
    esac

    # Ensure openssl is available (needed for password generation in prompts)
    if ! command_exists openssl; then
        info "Installing openssl (required for password generation)..."
        apt-get update -y -qq && apt-get install -y -qq openssl
    fi

    # Detect SSH port (so we don't lock the user out via UFW)
    detect_ssh_port

    # Init log file
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    log "Logging to $LOG_FILE"

    # Warn if a previous run exists
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        warn "Existing credentials file found: $CREDENTIALS_FILE"
        warn "Re-running may overwrite credentials and break existing sites."
        confirm "Continue anyway?" "N" || err "Aborted by user."
        # Preserve a backup
        cp -a "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.bak.$(date +%s)"
        log "Previous credentials backed up."
    fi

    export DEBIAN_FRONTEND=noninteractive
    export COMPOSER_ALLOW_SUPERUSER=1
}

# =============================================================================
#  SSH PORT DETECTION
# =============================================================================
detect_ssh_port() {
    local port=""

    # Helper: extract Port directive from a file, returning empty string on no match.
    # `|| true` is essential: grep returns 1 when no match, which kills `set -e` scripts.
    extract_port_from() {
        local file="$1"
        grep -hE "^[[:space:]]*Port[[:space:]]+" "$file" 2>/dev/null \
            | awk '{print $2}' | head -1 || true
    }

    # 1. Main sshd_config
    if [[ -f /etc/ssh/sshd_config ]]; then
        port=$(extract_port_from /etc/ssh/sshd_config)
    fi

    # 2. Drop-in configs (Ubuntu 24.04 uses /etc/ssh/sshd_config.d/*.conf)
    if [[ -z "$port" ]] && [[ -d /etc/ssh/sshd_config.d ]]; then
        local f
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -f "$f" ]] || continue
            port=$(extract_port_from "$f")
            [[ -n "$port" ]] && break
        done
    fi

    # 3. Live socket lookup as last resort
    if [[ -z "$port" ]] && command_exists ss; then
        port=$(ss -tlnH 2>/dev/null | awk '$4 ~ /:22$|:ssh$/ {split($4,a,":"); print a[length(a)]; exit}' || true)
    fi

    SSH_PORT="${port:-22}"
    log "Detected SSH port: $SSH_PORT"
}
