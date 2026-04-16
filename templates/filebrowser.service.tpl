[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/filebrowser -c {{FB_CONFIG_DIR}}/filebrowser.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
