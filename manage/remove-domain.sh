#!/bin/bash
###############################################################################
#  manage/remove-domain.sh — Remove a domain's vhost, optionally DB + files
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
###############################################################################

cmd_remove_domain() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage remove-domain <domain>"

    local conf="${NGINX_CONF_DIR}/${domain}.conf"
    [[ -f "$conf" ]] || err "No vhost found for '${domain}' at ${conf}"

    section "Remove domain: ${domain}"
    warn "This will remove the nginx vhost for ${domain}."
    confirm "Continue?" "N" || { info "Aborted."; return 0; }

    # Remove vhost config
    rm -f "$conf"
    log "Removed vhost: ${conf}"

    # Optionally drop database and user
    local db_name
    db_name=$(_domain_db_name "$domain")
    local db_user="${db_name}_user"

    if confirm "Also drop database '${db_name}' and user '${db_user}'?" "N"; then
        _read_mysql_root_pass
        mariadb -u root -p"${MYSQL_ROOT_PASS}" -e "DROP DATABASE IF EXISTS \`${db_name}\`;" 2>/dev/null || true
        mariadb -u root -p"${MYSQL_ROOT_PASS}" -e "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null || true
        log "Dropped database '${db_name}' and user '${db_user}'."
    fi

    # Optionally remove web root
    local web_root="${WEB_ROOT_BASE}/${domain}"
    if [[ -d "$web_root" ]]; then
        if confirm "Also delete web root '${web_root}'? THIS CANNOT BE UNDONE." "N"; then
            rm -rf "$web_root"
            log "Removed web root: ${web_root}"
        fi
    fi

    # Reload nginx
    if nginx -t 2>&1; then
        systemctl reload nginx
        log "Nginx reloaded."
    else
        warn "Nginx config test failed — check remaining vhosts."
    fi

    log "Domain '${domain}' removed."
}
