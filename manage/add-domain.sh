#!/bin/bash
###############################################################################
#  manage/add-domain.sh — Add a new domain with vhost, web root, and database
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Reuses _domains_create_vhost() from modules/95-domains.sh
#  and _databases_create_for_domain() from modules/99-databases.sh.
###############################################################################

cmd_add_domain() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage add-domain <domain>"

    _validate_domain_format "$domain" || err "Invalid domain format: ${domain}"
    ! _domain_exists "$domain" || err "Domain '${domain}' already has a vhost at ${NGINX_CONF_DIR}/${domain}.conf"

    # Populate globals needed by module functions
    _detect_nginx_user
    _read_mysql_root_pass

    section "Adding domain: ${domain}"

    # Create vhost, web root, and placeholder index.html
    _domains_create_vhost "$domain"

    # Create database and user, append credentials
    [[ -f "$CREDENTIALS_FILE" ]] || err "Credentials file not found: ${CREDENTIALS_FILE}"
    _databases_create_for_domain "$domain"

    # Test and reload nginx
    if ! nginx -t 2>&1; then
        err "Nginx config test failed. Check ${NGINX_CONF_DIR}/${domain}.conf"
    fi
    systemctl reload nginx

    log "Domain '${domain}' added successfully."
    echo ""
    info "Next step — issue an SSL certificate:"
    echo "  sudo certbot --nginx -d ${domain} -d www.${domain}"
    echo ""
}
