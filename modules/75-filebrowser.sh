#!/bin/bash
###############################################################################
#  modules/75-filebrowser.sh — File Browser with randomized URL path
#
#  Installs File Browser, creates systemd unit, configures JSON config.
#  URL path randomized (e.g. /files-d9e8f7g6). Nginx snippet for vhosts.
#  Runs as root via systemd (required for web root file management).
#
#  Depends on: lib/core.sh (logging, constants, command_exists, FB_PATH global)
#              lib/utils.sh (generate_url_token)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_filebrowser_describe() {
    echo "File Browser — randomized URL path"
}

module_filebrowser_check() {
    command_exists filebrowser && state_is_installed "filebrowser"
}

module_filebrowser_install() {
    section "Installing File Browser"

    FB_PATH="/files-$(generate_url_token)"

    _filebrowser_install_binary
    _filebrowser_configure
    _filebrowser_setup_service
    _filebrowser_set_credentials
    _filebrowser_write_nginx_snippet

    log "File Browser installed at random path: ${FB_PATH}"
    state_mark_installed "filebrowser"
}

# --- Private helpers --------------------------------------------------------

_filebrowser_install_binary() {
    if ! command_exists filebrowser; then
        curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    else
        info "File Browser already installed."
    fi
}

_filebrowser_configure() {
    mkdir -p "$FB_CONFIG_DIR" "$FB_DATA_DIR"

    cat > "${FB_CONFIG_DIR}/filebrowser.json" <<FBEOF
{
  "port": ${FB_PORT},
  "baseURL": "${FB_PATH}",
  "address": "127.0.0.1",
  "log": "/var/log/filebrowser.log",
  "database": "${FB_DATA_DIR}/filebrowser.db",
  "root": "${WEB_ROOT_BASE}",
  "noAuth": false
}
FBEOF
    chmod 640 "${FB_CONFIG_DIR}/filebrowser.json"
}

_filebrowser_setup_service() {
    cat > /etc/systemd/system/filebrowser.service <<FBSVCEOF
[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/filebrowser -c ${FB_CONFIG_DIR}/filebrowser.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FBSVCEOF

    systemctl daemon-reload
    systemctl enable --now filebrowser
    sleep 2
}

_filebrowser_set_credentials() {
    # Set credentials (idempotent: try update first, then add)
    filebrowser users update "${FB_USER}" --password="${FB_PASS}" \
        -d "${FB_DATA_DIR}/filebrowser.db" 2>/dev/null || \
    filebrowser users add "${FB_USER}" "${FB_PASS}" --perm.admin \
        -d "${FB_DATA_DIR}/filebrowser.db" 2>/dev/null || \
        warn "Could not set File Browser admin credentials automatically."
}

_filebrowser_write_nginx_snippet() {
    cat > "${NGINX_SNIPPETS_DIR}/filebrowser.conf" <<FBINCEOF
location ${FB_PATH} {
    proxy_pass http://127.0.0.1:${FB_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_redirect off;
    proxy_buffering off;
    client_max_body_size 0;

    limit_req zone=admin burst=20 nodelay;
}
FBINCEOF
}
