#!/bin/bash
###############################################################################
#  manage/ssl-remove.sh — Delete a Let's Encrypt certificate
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssl-remove <domain>
#
#  Runs `certbot delete --cert-name <domain>`. Certbot's --nginx plugin had
#  injected SSL directives into the vhost at issue time; those now point at
#  non-existent cert files, so nginx -t would fail on next reload.
#  We offer to regenerate the vhost from the default template.
###############################################################################

cmd_ssl_remove() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage ssl-remove <domain>"

    command_exists certbot || err "certbot not installed."

    _validate_domain_format "$domain" || err "Invalid domain format: ${domain}"
    [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]] \
        || err "No SSL certificate found for '${domain}'."

    section "Remove SSL — ${domain}"
    warn "This will delete the Let's Encrypt certificate for ${domain}."
    confirm "Continue?" "N" || { info "Aborted."; return 0; }

    if ! certbot delete --cert-name "$domain" --non-interactive; then
        err "certbot delete failed."
    fi
    log "Certificate deleted for ${domain}"

    # The vhost still has SSL directives that now reference deleted files.
    # Offer to regenerate it from our template (clean HTTP-only config).
    local vhost="${NGINX_CONF_DIR}/${domain}.conf"
    if [[ -f "$vhost" ]] && grep -qE '(listen 443|ssl_certificate)' "$vhost"; then
        echo ""
        warn "The vhost still references the deleted certificate:"
        warn "  ${vhost}"
        warn "nginx -t will fail until this is fixed."
        echo ""
        if confirm "Regenerate ${domain}.conf from the default template? (drops any manual edits)" "Y"; then
            _detect_nginx_user
            _domains_create_vhost "$domain"
            if nginx -t 2>&1; then
                systemctl reload nginx
                log "Vhost regenerated; nginx reloaded."
            else
                warn "nginx -t still failing. Inspect ${vhost} manually."
            fi
        else
            warn "Edit ${vhost} manually, then: systemctl reload nginx"
        fi
    else
        # Vhost already clean (no SSL blocks) — just reload.
        if nginx -t 2>&1; then
            systemctl reload nginx
            log "Nginx reloaded."
        fi
    fi

    log "SSL removed for ${domain}"
}
