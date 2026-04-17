#!/bin/bash
###############################################################################
#  manage/ssl-issue.sh — Issue a Let's Encrypt certificate for a domain
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssl-issue <domain>
#
#  Wraps `certbot --nginx -d <domain> [-d www.<domain>]`. The www alias is
#  included automatically if it appears in the vhost's server_name line.
#  Certbot handles its own email/TOS prompts on first run.
###############################################################################

cmd_ssl_issue() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage ssl-issue <domain>"

    command_exists certbot || err "certbot not installed. Run the installer first."

    _validate_domain_format "$domain" || err "Invalid domain format: ${domain}"
    _domain_exists "$domain" || err "No vhost found for '${domain}'. Add it first with: lemp-manage add-domain ${domain}"

    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        err "SSL certificate already exists for '${domain}'. Use ssl-renew to renew it."
    fi

    section "Issue SSL — ${domain}"

    # Extract server_name aliases from the vhost. Include only the canonical
    # www alias (we don't want to grab unrelated server_names on the same block).
    local cert_args=(-d "$domain")
    local server_names
    server_names=$(grep -oP '^\s*server_name\s+\K[^;]+' "${NGINX_CONF_DIR}/${domain}.conf" | head -1 || true)
    local n
    for n in $server_names; do
        [[ "$n" == "www.${domain}" ]] && cert_args+=(-d "$n")
    done

    info "Requesting certificate: certbot --nginx ${cert_args[*]}"
    info "Certbot will prompt for your email and TOS agreement on first run."
    echo ""

    if ! certbot --nginx "${cert_args[@]}"; then
        err "Certbot failed. Common causes: DNS not pointing to this server, port 80 blocked, or Let's Encrypt rate limit."
    fi

    log "SSL certificate issued for ${domain}"
    [[ ${#cert_args[@]} -gt 2 ]] && log "Also covering: www.${domain}"
}
