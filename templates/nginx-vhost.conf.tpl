# Template: Nginx virtual host configuration
# Placeholders: {{DOMAIN}}, {{SITE_ROOT}}, {{PHP_VERSION}}, {{PHP_MAX_EXEC_TIME}},
#               {{PHP_UPLOAD_MAX}}, {{NGINX_SNIPPETS_DIR}}
# Rendered by: render_template() in lib/utils.sh

server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}} www.{{DOMAIN}};
    root {{SITE_ROOT}};
    # Full configuration will be migrated from server-setup.sh
}
