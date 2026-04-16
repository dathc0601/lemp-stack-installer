#!/bin/bash
###############################################################################
#  lib/state.sh — Installation state tracking (idempotency/rollback)
#
#  State file: /var/lib/server-setup/state
#  Format: one line per installed module — "name version timestamp"
#
#  Pure function definitions — no side effects on source.
#  Depends on: lib/core.sh (STATE_DIR, STATE_FILE, INSTALLER_VERSION, logging)
###############################################################################

# =============================================================================
#  INTERNAL
# =============================================================================

# Ensure the state directory and file exist. Called lazily by public functions.
_state_init() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR"
    fi
    if [[ ! -f "$STATE_FILE" ]]; then
        touch "$STATE_FILE"
        chmod 600 "$STATE_FILE"
    fi
}

# =============================================================================
#  PUBLIC API
# =============================================================================

# Record a module as installed (or update its entry if already present).
# Usage: state_mark_installed "redis" ["1.0.0"]
# If version is omitted, uses INSTALLER_VERSION.
state_mark_installed() {
    local name="$1"
    local version="${2:-${INSTALLER_VERSION}}"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    _state_init

    # Remove any existing entry for this module, then append the new one.
    # grep -v may match nothing — || true prevents set -e from killing us.
    local tmp
    tmp=$(grep -v "^${name} " "$STATE_FILE" 2>/dev/null || true)
    echo "$tmp" > "$STATE_FILE"
    echo "${name} ${version} ${timestamp}" >> "$STATE_FILE"

    # Clean up blank lines that accumulate from grep -v on single-entry files
    sed -i '/^$/d' "$STATE_FILE"
}

# Check if a module is recorded as installed. Returns 0 (true) or 1 (false).
# Usage: state_is_installed "redis" && echo "yes"
state_is_installed() {
    local name="$1"
    _state_init
    grep -q "^${name} " "$STATE_FILE" 2>/dev/null
}

# Get the installed version of a module. Prints version string or empty.
# Usage: ver=$(state_get_version "redis")
state_get_version() {
    local name="$1"
    _state_init
    grep "^${name} " "$STATE_FILE" 2>/dev/null | awk '{print $2}' || true
}

# List all installed modules. One line per module: "name version timestamp"
# Usage: state_list
state_list() {
    _state_init
    if [[ -s "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        info "No modules installed yet."
    fi
}
