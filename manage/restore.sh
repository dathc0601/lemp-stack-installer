#!/bin/bash
###############################################################################
#  manage/restore.sh — Restore from backup
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage restore <backup-path> <domain>
#  backup-path is the domain subdirectory, e.g.:
#    /var/backups/server-setup/2025-01-15/example.com
###############################################################################

cmd_restore() {
    local backup_path="${1:-}"
    local domain="${2:-}"
    [[ -n "$backup_path" && -n "$domain" ]] || err "Usage: lemp-manage restore <backup-path> <domain>"
    [[ -d "$backup_path" ]] || err "Backup path not found: ${backup_path}"

    # Verify backup has at least one restorable artifact
    local has_webroot=0 has_db=0
    [[ -f "${backup_path}/webroot.tar.gz" ]] && has_webroot=1
    [[ -f "${backup_path}/database.sql.gz" ]] && has_db=1
    [[ $has_webroot -eq 1 || $has_db -eq 1 ]] || err "No webroot.tar.gz or database.sql.gz found in ${backup_path}"

    section "Restore: ${domain}"
    info "From: ${backup_path}"
    [[ $has_webroot -eq 1 ]] && info "  Web root : will be restored"
    [[ $has_db -eq 1 ]] && info "  Database : will be restored"
    echo ""
    warn "This will overwrite current data for '${domain}'."
    confirm "Continue?" "N" || { info "Aborted."; return 0; }

    _detect_nginx_user

    # Restore web root
    if [[ $has_webroot -eq 1 ]]; then
        local web_root="${WEB_ROOT_BASE}/${domain}"
        info "Restoring web root..."
        mkdir -p "$web_root"
        rm -rf "${web_root:?}/"*
        tar -xzf "${backup_path}/webroot.tar.gz" -C "$WEB_ROOT_BASE"
        chown -R "${NGINX_USER}:${NGINX_USER}" "$web_root"
        chmod -R 755 "$web_root"
        log "Web root restored: ${web_root}"
    fi

    # Restore database
    if [[ $has_db -eq 1 ]]; then
        info "Restoring database..."
        _read_mysql_root_pass

        local db_name
        db_name=$(_domain_db_name "$domain")

        # Create DB if it doesn't exist
        mariadb -u root -p"${MYSQL_ROOT_PASS}" -e \
            "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null

        gunzip -c "${backup_path}/database.sql.gz" | mariadb -u root -p"${MYSQL_ROOT_PASS}" "$db_name" 2>/dev/null
        log "Database restored: ${db_name}"
    fi

    log "Restore complete for '${domain}'."
}
