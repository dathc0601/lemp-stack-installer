#!/bin/bash
###############################################################################
#  manage/db-user-password.sh — Rotate the password for a DB user
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage db-user-password [db_name]
#
#  If the DB has multiple users, prompts for which one. Updates the
#  credentials file's "DB pass" line for the owning block (either the
#  [domain] block or a [db:name] block). When the DB is not tracked in
#  credentials, warns but still rotates in MariaDB.
###############################################################################

cmd_db_user_password() {
    local db_name="${1:-}"

    section "Change DB user password"

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
    _db_exists "$db_name" || err "Database '${db_name}' does not exist."

    # --- Pick the user --------------------------------------------------------
    local users=()
    local u
    while IFS= read -r u; do
        [[ -n "$u" ]] && users+=("$u")
    done < <(mariadb -u root -p"${MYSQL_ROOT_PASS}" -N -B -e \
        "SELECT User FROM mysql.db WHERE Db='${db_name}' AND Host='localhost';" 2>/dev/null || true)

    if [[ ${#users[@]} -eq 0 ]]; then
        err "No users found with access to '${db_name}' (at localhost). Grant access first."
    fi

    local db_user
    if [[ ${#users[@]} -eq 1 ]]; then
        db_user="${users[0]}"
        info "Rotating password for user '${db_user}'@localhost (sole grantee of ${db_name})."
    else
        echo ""
        local i=1
        for u in "${users[@]}"; do
            printf "  %d) %s\n" "$i" "$u"
            i=$((i + 1))
        done
        echo ""
        local reply
        read -rp "─// Select user (1-${#users[@]}) [0=Cancel]: " reply || { info "Aborted."; return 0; }
        [[ "$reply" == "0" ]] && { info "Aborted."; return 0; }
        [[ "$reply" =~ ^[0-9]+$ ]] || err "Invalid selection: ${reply}"
        [[ "$reply" -ge 1 && "$reply" -le ${#users[@]} ]] || err "Out of range."
        db_user="${users[$((reply - 1))]}"
    fi

    # --- New password ---------------------------------------------------------
    local new_pass=""
    _prompt_password_or_generate new_pass "New"

    # --- Rotate in MariaDB ----------------------------------------------------
    mariadb -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL || err "ALTER USER failed."
ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}';
FLUSH PRIVILEGES;
EOSQL

    # --- Update credentials file (owning block, whichever it is) --------------
    local owner
    owner=$(_find_db_owner "$db_name" || true)
    if [[ -z "$owner" ]]; then
        warn "Database '${db_name}' not tracked in ${CREDENTIALS_FILE}."
        warn "Password rotated in MariaDB only — record it manually if you need to recover it."
    else
        _update_cred_field "$owner" "DB pass" "$new_pass" \
            || warn "Rotated in MariaDB but failed to update ${CREDENTIALS_FILE}. Fix the file manually."
    fi

    new_pass=""
    log "Password rotated for '${db_user}'@localhost on database '${db_name}'."
}
