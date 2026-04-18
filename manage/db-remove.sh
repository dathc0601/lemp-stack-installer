#!/bin/bash
###############################################################################
#  manage/db-remove.sh — Drop a database + its dedicated users
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-remove <db_name>
#
#  Refuses system DBs. Warns loudly when the DB is linked to a domain —
#  deleting it will break that site. Drops each granted user IFF they have
#  no other DB grants; otherwise leaves the user alone.
#
#  Credentials cleanup: removes a matching [db:${name}] block. Leaves a
#  [${domain}] block alone — remove-domain owns that flow.
###############################################################################

cmd_db_remove() {
    local db_name="${1:-}"

    section "Delete database"

    _read_mysql_root_pass

    if [[ -z "$db_name" ]]; then
        if declare -f _menu_pick_database >/dev/null; then
            db_name=$(_menu_pick_database "all") || { info "Aborted."; return 0; }
        else
            read -rp "─// Database name: " db_name || { info "Aborted."; return 0; }
        fi
    fi
    [[ -n "$db_name" ]] || err "Empty database name."
    _validate_db_name "$db_name" \
        || err "Invalid name '${db_name}': only [a-zA-Z0-9_] allowed, max 64 chars."

    case "$db_name" in
        mysql|information_schema|performance_schema|sys)
            err "Refusing to drop system database '${db_name}'." ;;
    esac

    _db_exists "$db_name" || err "Database '${db_name}' does not exist."

    # --- Warn if linked to a domain ------------------------------------------
    local owner linked_domain=""
    owner=$(_find_db_owner "$db_name" || true)
    if [[ -n "$owner" && "$owner" != \[db:* ]]; then
        linked_domain="${owner#\[}"
        linked_domain="${linked_domain%\]}"
        warn "Database '${db_name}' is linked to domain '${linked_domain}'."
        warn "Deleting it will break that site. Use 'remove-domain' if you want"
        warn "to cleanly tear down the whole site (vhost + files + DB together)."
    fi

    # --- Find users that would need to go with it -----------------------------
    local users=() u
    while IFS= read -r u; do
        [[ -n "$u" ]] && users+=("$u")
    done < <(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT DISTINCT User FROM mysql.db WHERE Db='${db_name}' AND Host='localhost';" 2>/dev/null || true)

    echo ""
    info "This will: DROP DATABASE \`${db_name}\`; then drop ${#users[@]} user(s) that have no other grants."
    confirm "Proceed?" "N" || { info "Aborted."; return 0; }

    # --- Drop DB -------------------------------------------------------------
    mariadb -u root -p"${MYSQL_ROOT_PASS}" -e "DROP DATABASE \`${db_name}\`;" \
        || err "DROP DATABASE failed."

    # --- Drop each user IFF they have no remaining grants --------------------
    local dropped=0 kept=0 remaining
    for u in "${users[@]}"; do
        remaining=$(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
            "SELECT COUNT(*) FROM mysql.db WHERE User='${u}' AND Host='localhost';" 2>/dev/null || echo "0")
        if [[ "$remaining" == "0" ]]; then
            mariadb -u root -p"${MYSQL_ROOT_PASS}" -e \
                "DROP USER IF EXISTS '${u}'@'localhost'; FLUSH PRIVILEGES;" \
                || warn "Failed to drop user '${u}'@localhost — continuing."
            dropped=$((dropped + 1))
        else
            kept=$((kept + 1))
            info "User '${u}'@localhost still has ${remaining} other grant(s) — left in place."
        fi
    done

    # --- Clean standalone credentials block (only [db:name], never [domain]) -
    if [[ "$owner" == \[db:* ]]; then
        _remove_cred_block "$owner"
        info "Removed ${owner} from ${CREDENTIALS_FILE}."
    elif [[ -n "$linked_domain" ]]; then
        info "Left the [${linked_domain}] block in ${CREDENTIALS_FILE} — use 'remove-domain ${linked_domain}' to clean it up."
    fi

    log "Dropped database '${db_name}'. Users dropped: ${dropped}, kept: ${kept}."
}
