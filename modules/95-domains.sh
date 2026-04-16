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

    render_template "nginx-vhost.conf.tpl" \
        "DOMAIN" "$domain" \
        "SITE_ROOT" "$site_root" \
        "PHP_VERSION" "$PHP_VERSION" \
        "PHP_UPLOAD_MAX" "$PHP_UPLOAD_MAX" \
        "PHP_MAX_EXEC_TIME" "$PHP_MAX_EXEC_TIME" \
        "NGINX_SNIPPETS_DIR" "$NGINX_SNIPPETS_DIR" \
        > "$nginx_conf"

    log "Vhost created: ${domain} → ${site_root}"
}

_domains_create_default_vhost() {
    info "Creating default catch-all vhost..."
    render_template "nginx-default.conf.tpl" \
        > "${NGINX_CONF_DIR}/000-default.conf"
}

_domains_cleanup_defaults() {
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/sites-enabled/default
}
