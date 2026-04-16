#!/bin/bash
###############################################################################
#  lib/utils.sh — Utility helpers
#
#  Pure function definitions — no side effects on source.
#  Depends on: lib/core.sh (constants, logging)
###############################################################################

# =============================================================================
#  PASSWORD & TOKEN GENERATION
# =============================================================================

# Generate a URL-safe random password of N chars (default 24)
generate_password() {
    local len="${1:-24}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$len"
}

# Generate a short hex token for URL paths (e.g. "a3f2b1c4")
generate_url_token() {
    openssl rand -hex 4
}

# =============================================================================
#  INTERACTIVE HELPERS
# =============================================================================

# Confirm yes/no, default No
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local hint="[y/N]"
    [[ "$default" =~ ^[Yy]$ ]] && hint="[Y/n]"
    local reply
    read -rp "$prompt $hint: " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

# =============================================================================
#  APT WRAPPERS  (non-interactive, safe for set -e)
# =============================================================================

# Run apt-get install with safe non-interactive defaults
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confdef" \
        "$@"
}

apt_update() {
    DEBIAN_FRONTEND=noninteractive apt-get update -y
}

apt_upgrade() {
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confdef"
}

# =============================================================================
#  TEMPLATE ENGINE
# =============================================================================

# Render a template file from templates/ by replacing {{PLACEHOLDER}} markers.
# Usage:
#   render_template "nginx-vhost.conf.tpl" \
#       "DOMAIN" "$domain" \
#       "SITE_ROOT" "$site_root" \
#       > "/etc/nginx/conf.d/${domain}.conf"
render_template() {
    local template="$1"; shift
    local content
    content=$(<"${SCRIPT_DIR}/templates/${template}")
    while [[ $# -gt 0 ]]; do
        content="${content//\{\{$1\}\}/$2}"
        shift 2
    done
    echo "$content"
}
