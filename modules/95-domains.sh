#!/bin/bash
###############################################################################
#  modules/95-domains.sh — Nginx vhost creation for configured domains
#
#  Creates per-domain vhost configs, web roots, placeholder HTML.
#  Creates default catch-all vhost (returns 444).
#  Includes security headers, rate limiting, admin tool snippets.
#
#  Depends on: lib/core.sh (logging, constants, NGINX_USER, DOMAINS)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_domains_describe() {
    echo "Domain vhosts — nginx configuration"
}

module_domains_check() {
    state_is_installed "domains"
}

module_domains_install() {
    section "Configuring domain vhosts"

    for domain in "${DOMAINS[@]}"; do
        _domains_create_vhost "$domain"
    done

    _domains_create_default_vhost
    _domains_cleanup_defaults

    nginx -t && systemctl reload nginx
    log "Nginx reloaded with all vhosts."
    state_mark_installed "domains"
}

# --- Private helpers --------------------------------------------------------

_domains_create_vhost() {
    local domain="$1"
    local site_root="${WEB_ROOT_BASE}/${domain}"
    local nginx_conf="${NGINX_CONF_DIR}/${domain}.conf"

    mkdir -p "$site_root"
    chown -R "${NGINX_USER}:${NGINX_USER}" "$site_root"
    chmod -R 755 "$site_root"

    # Safe placeholder — does NOT leak server info (unlike phpinfo)
    if [[ ! -f "${site_root}/index.html" ]] && [[ ! -f "${site_root}/index.php" ]]; then
        cat > "${site_root}/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>${domain}</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 600px;
               margin: 4rem auto; padding: 0 1rem; color: #333; }
        h1 { color: #2c3e50; }
        code { background: #f4f4f4; padding: 0.2em 0.4em; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>${domain}</h1>
    <p>This site is ready. Replace <code>${site_root}/index.html</code> with your content.</p>
</body>
</html>
HTMLEOF
        chown "${NGINX_USER}:${NGINX_USER}" "${site_root}/index.html"
    fi

    cat > "$nginx_conf" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    root ${site_root};
    index index.php index.html index.htm;

    access_log /var/log/nginx/${domain}.access.log;
    error_log  /var/log/nginx/${domain}.error.log;

    client_max_body_size ${PHP_UPLOAD_MAX};

    include ${NGINX_SNIPPETS_DIR}/security-headers.conf;

    # WordPress-style pretty permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Rate-limit login endpoints
    location = /wp-login.php {
        limit_req zone=login burst=2 nodelay;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout ${PHP_MAX_EXEC_TIME};
    }

    location ~ \\.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_intercept_errors on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout ${PHP_MAX_EXEC_TIME};
    }

    # Block hidden files
    location ~ /\\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Block sensitive files
    location ~* /(?:wp-config\\.php|readme\\.html|license\\.txt|\\.env|composer\\.(json|lock))\$ {
        deny all;
    }

    # Block xmlrpc — frequent attack vector
    location = /xmlrpc.php {
        deny all;
    }

    # Static asset caching
    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf|eot)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               image/svg+xml;

    # Admin tools (random paths for obscurity)
    include ${NGINX_SNIPPETS_DIR}/phpmyadmin.conf;
    include ${NGINX_SNIPPETS_DIR}/filebrowser.conf;
}
NGINXEOF

    log "Vhost created: ${domain} → ${site_root}"
}

_domains_create_default_vhost() {
    info "Creating default catch-all vhost..."
    # Direct-IP hits & unknown hostnames: drop the connection.
    # Admin tools are accessible ONLY via configured domains.
    cat > "${NGINX_CONF_DIR}/000-default.conf" <<'EOF'
# Default catch-all — silently drop requests for unknown hosts / direct IP access.
# Admin tools are accessible ONLY via your configured domains.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF
}

_domains_cleanup_defaults() {
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/sites-enabled/default
}
