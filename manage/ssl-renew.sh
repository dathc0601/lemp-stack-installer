#!/bin/bash
###############################################################################
#  manage/ssl-renew.sh — Renew Let's Encrypt certificates
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssl-renew [domain]
#
#  With <domain>: force-renew that single certificate.
#  Without args : run `certbot renew` for all certs (no-op unless near expiry).
#
#  Note: certbot's systemd timer already handles routine auto-renewal. This
#  command is for forced renewal or manual troubleshooting.
###############################################################################

cmd_ssl_renew() {
    local domain="${1:-}"

    command_exists certbot || err "certbot not installed."

    if [[ -n "$domain" ]]; then
        _validate_domain_format "$domain" || err "Invalid domain format: ${domain}"
        [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]] \
            || err "No SSL certificate found for '${domain}'."

        section "Renew SSL — ${domain}"
        info "Forcing renewal for ${domain}..."
        if ! certbot renew --cert-name "$domain" --force-renewal; then
            err "certbot renew failed for ${domain}."
        fi
        log "Certificate renewed for ${domain}"
    else
        section "Renew SSL — all domains"
        info "Running renewal check for all certificates..."
        info "(Only certs within 30 days of expiry will actually renew.)"
        echo ""
        if ! certbot renew; then
            err "certbot renew failed."
        fi
        log "Renewal check complete."
    fi
}
