#!/bin/bash
###############################################################################
#  modules/20-nginx.sh — Nginx mainline from official repo
#
#  Installs nginx from nginx.org (not Ubuntu distro package).
#  Detects nginx user dynamically from nginx.conf.
#  Configures global rate-limit zones and security headers snippet.
#
#  Depends on: lib/core.sh (logging, constants, command_exists, NGINX_USER global)
#              lib/utils.sh (apt_install)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_nginx_describe() {
    echo "Nginx — mainline from nginx.org"
}

module_nginx_check() {
    command_exists nginx && state_is_installed "nginx"
}

module_nginx_install() {
    section "Installing Nginx"
    _nginx_install_packages
    _nginx_detect_user
    _nginx_configure_globals
    mkdir -p "$NGINX_SNIPPETS_DIR"
    systemctl enable --now nginx
    log "Nginx ready (running as user: $NGINX_USER)"
    state_mark_installed "nginx"
}

# --- Private helpers --------------------------------------------------------

_nginx_install_packages() {
    if ! command_exists nginx; then
        curl -fsSL https://nginx.org/keys/nginx_signing.key \
            | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

        echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu ${OS_CODENAME} nginx" \
            > /etc/apt/sources.list.d/nginx.list

        cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF
        apt_update
        apt_install nginx
    else
        info "Nginx already installed: $(nginx -v 2>&1)"
    fi
}

# Detect whether nginx runs as 'nginx' (nginx.org build) or 'www-data' (distro build)
_nginx_detect_user() {
    # Check the actual nginx.conf user directive first
    if [[ -f /etc/nginx/nginx.conf ]]; then
        local cfg_user
        cfg_user=$(grep -E "^[[:space:]]*user[[:space:]]+" /etc/nginx/nginx.conf 2>/dev/null \
                   | awk '{print $2}' | tr -d ';' | head -1 || true)
        if [[ -n "$cfg_user" ]] && id "$cfg_user" &>/dev/null; then
            NGINX_USER="$cfg_user"
            return
        fi
    fi
    # Fall back to checking which user exists
    if id nginx &>/dev/null; then
        NGINX_USER="nginx"
    elif id www-data &>/dev/null; then
        NGINX_USER="www-data"
    else
        err "Could not detect Nginx user."
    fi
}

# Write global rate-limit zones and security headers snippet
_nginx_configure_globals() {
    section "Configuring Nginx security headers & rate limits"

    # Rate-limit zones (must be in http context — conf.d files are included there)
    cat > "${NGINX_CONF_DIR}/00-rate-limits.conf" <<'EOF'
# Rate limiting zones — applied selectively to login/admin endpoints
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=admin:10m rate=30r/m;
limit_req_status 429;
EOF

    # Security headers snippet — included in every server block
    cat > "${NGINX_SNIPPETS_DIR}/security-headers.conf" <<'EOF'
# Security headers (apply to all responses, including errors)
add_header X-Frame-Options              "SAMEORIGIN"                       always;
add_header X-Content-Type-Options       "nosniff"                          always;
add_header Referrer-Policy              "strict-origin-when-cross-origin"  always;
add_header X-XSS-Protection             "1; mode=block"                    always;
add_header Permissions-Policy           "geolocation=(), microphone=(), camera=()" always;
# HSTS — browsers ignore this on HTTP, so it's safe to set unconditionally
add_header Strict-Transport-Security    "max-age=31536000; includeSubDomains" always;

# Hide nginx version
server_tokens off;
EOF

    log "Global Nginx config written."
}
