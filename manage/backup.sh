#!/bin/bash
###############################################################################
#  manage/backup.sh — Backup databases and web roots
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage backup [domain]
#  If domain is omitted, backs up all configured domains.
#  Backups stored at /var/backups/server-setup/YYYY-MM-DD/<domain>/
###############################################################################

cmd_backup() {
    local target_domain="${1:-}"
    local date_stamp
    date_stamp=$(date '+%Y-%m-%d')
    local backup_base="/var/backups/server-setup/${date_stamp}"

    _read_mysql_root_pass

    # Build domain list
    local domains=()
    if [[ -n "$target_domain" ]]; then
        _domain_exists "$target_domain" || err "No vhost found for '${target_domain}'."
        domains=("$target_domain")
    else
        local conf
        for conf in "${NGINX_CONF_DIR}"/*.conf; do
            [[ -f "$conf" ]] || continue
            local name
            name=$(basename "$conf" .conf)
            [[ "$name" == "000-default" ]] && continue
            domains+=("$name")
        done
    fi

    [[ ${#domains[@]} -gt 0 ]] || err "No domains found to back up."

    mkdir -p "$backup_base"
    section "Backup — ${date_stamp}"
    info "Backing up ${#domains[@]} domain(s) to ${backup_base}"

    for domain in "${domains[@]}"; do
        local domain_backup="${backup_base}/${domain}"
        mkdir -p "$domain_backup"

        # Backup web root
        local web_root="${WEB_ROOT_BASE}/${domain}"
        if [[ -d "$web_root" ]]; then
            tar -czf "${domain_backup}/webroot.tar.gz" -C "$WEB_ROOT_BASE" "$domain"
            log "Backed up web root: ${domain}"
        else
            warn "No web root for ${domain} — skipping files."
        fi

        # Backup database (if it exists)
        local db_name
        db_name=$(_domain_db_name "$domain")
        local db_exists
        db_exists=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
            "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${db_name}';" 2>/dev/null || echo "0")

        if [[ "$db_exists" == "1" ]]; then
            mysqldump -u root -p"${MYSQL_ROOT_PASS}" "$db_name" 2>/dev/null \
                | gzip > "${domain_backup}/database.sql.gz"
            log "Backed up database: ${db_name}"
        else
            warn "No database '${db_name}' found — skipping DB backup."
        fi
    done

    # Report total size
    local total_size
    total_size=$(du -sh "$backup_base" | awk '{print $1}' || true)
    echo ""
    log "Backup complete: ${backup_base} (${total_size})"
}
