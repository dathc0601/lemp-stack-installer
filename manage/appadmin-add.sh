#!/bin/bash
###############################################################################
#  manage/appadmin-add.sh — Add an admin user to phpMyAdmin or File Browser
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-add [pma|fb] [username]
#
#  PMA branch: writes to /etc/nginx/.htpasswd-pma (bcrypt). On pre-feature
#  installs where auth_basic isn't in the snippet yet, this also patches the
#  snippet to enable auth_basic — one-shot upgrade path.
#
#  FB branch: calls `filebrowser users add <user> <pass> --perm.admin -d DB`.
###############################################################################

# Silent 2× password prompt, min 12 chars. Stores result in the referenced var.
_appadmin_prompt_password() {
    local -n out_ref="$1"
    local label="${2:-new}"
    local pass1 pass2
    while true; do
        read -rsp "  ${label} password (min 12 chars): " pass1; echo ""
        if [[ -z "$pass1" ]]; then
            warn "Empty password not allowed."
            continue
        fi
        if [[ ${#pass1} -lt 12 ]]; then
            warn "Password too short (${#pass1} chars; minimum 12). Try again."
            continue
        fi
        read -rsp "  Confirm                         : " pass2; echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            warn "Passwords don't match. Try again."
            continue
        fi
        out_ref="$pass1"
        pass1=""; pass2=""
        return 0
    done
}

# Re-render the phpMyAdmin nginx snippet from the template so auth_basic gets
# added for existing installs (the heredoc-era snippet lacks those directives).
# Preserves the currently-used PMA_PATH by reading it from the existing snippet.
_appadmin_patch_pma_snippet() {
    local snippet="${NGINX_SNIPPETS_DIR}/phpmyadmin.conf"
    [[ -f "$snippet" ]] || err "Missing nginx snippet: ${snippet}. Re-run the phpMyAdmin module."

    if grep -q 'auth_basic' "$snippet"; then
        return 0  # already patched
    fi

    info "Patching nginx snippet to enable auth_basic (one-time upgrade)..."
    local pma_path
    pma_path=$(grep -m1 '^location ' "$snippet" | awk '{print $2}' || true)
    [[ -n "$pma_path" ]] || err "Could not detect PMA_PATH from ${snippet}."

    cp -a "$snippet" "${snippet}.bak-$(date -u +%Y%m%d%H%M%S)"

    local tmp
    tmp=$(mktemp)
    render_template "nginx-phpmyadmin.conf.tpl" \
        "PMA_PATH" "$pma_path" \
        "PMA_DIR" "$PMA_DIR" \
        "PHP_VERSION" "$PHP_VERSION" \
        "PHP_MAX_EXEC_TIME" "$PHP_MAX_EXEC_TIME" \
        "PMA_HTPASSWD_FILE" "$PMA_HTPASSWD_FILE" \
        > "$tmp"
    mv "$tmp" "$snippet"

    if ! nginx -t >/dev/null 2>&1; then
        # Restore on failure — never leave nginx broken
        local latest_bak
        latest_bak=$(ls -t "${snippet}.bak-"* 2>/dev/null | head -1 || true)
        [[ -n "$latest_bak" ]] && mv "$latest_bak" "$snippet"
        err "nginx -t failed after snippet patch; original restored from ${latest_bak:-backup}."
    fi
    systemctl reload nginx || err "nginx reload failed after snippet patch."
    log "phpMyAdmin snippet upgraded — auth_basic now active."
}

_appadmin_add_pma() {
    local user="$1" pass="$2"

    _detect_nginx_user  # ensures NGINX_USER is set for chown

    if [[ ! -f "$PMA_HTPASSWD_FILE" ]]; then
        info "Creating ${PMA_HTPASSWD_FILE} (first PMA admin user)..."
        htpasswd -cbB "$PMA_HTPASSWD_FILE" "$user" "$pass" >/dev/null \
            || err "htpasswd -cbB failed."
        chown "root:${NGINX_USER}" "$PMA_HTPASSWD_FILE"
        chmod 640 "$PMA_HTPASSWD_FILE"
    else
        # Refuse duplicate — update is a separate command (appadmin-password)
        if grep -q "^${user}:" "$PMA_HTPASSWD_FILE"; then
            err "User '${user}' already exists in ${PMA_HTPASSWD_FILE}. Use appadmin-password to change their password."
        fi
        htpasswd -bB "$PMA_HTPASSWD_FILE" "$user" "$pass" >/dev/null \
            || err "htpasswd -bB failed."
    fi

    # Self-heal: ensure the nginx snippet has auth_basic directives
    _appadmin_patch_pma_snippet

    log "Added phpMyAdmin admin user '${user}'."
}

_appadmin_add_fb() {
    local user="$1" pass="$2"
    command_exists filebrowser || err "filebrowser CLI not found. Is the filebrowser module installed?"
    local db="${FB_DATA_DIR}/filebrowser.db"
    [[ -f "$db" ]] || err "File Browser database not found: ${db}"
    if ! filebrowser users add "$user" "$pass" --perm.admin -d "$db" >/dev/null 2>&1; then
        err "filebrowser users add failed — user '${user}' may already exist. Use appadmin-password to change their password."
    fi
    log "Added File Browser admin user '${user}'."
}

cmd_appadmin_add() {
    local app="${1:-}" user="${2:-}"

    section "Add admin user"

    # --- Pick app (pma|fb) ----------------------------------------------------
    if [[ -z "$app" ]]; then
        if declare -f _menu_pick_admin_app >/dev/null; then
            app=$(_menu_pick_admin_app) || { info "Aborted."; return 0; }
        else
            read -rp "─// App [pma|fb]: " app || { info "Aborted."; return 0; }
        fi
    fi
    case "$app" in
        pma|fb) ;;
        *) err "Invalid app: '${app}'. Expected 'pma' or 'fb'." ;;
    esac

    # --- Pick username --------------------------------------------------------
    if [[ -z "$user" ]]; then
        read -rp "─// Username to add: " user || { info "Aborted."; return 0; }
    fi
    [[ -n "$user" ]] || err "Empty username."
    [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]] \
        || err "Invalid username '${user}': only [a-zA-Z0-9_.-] allowed."

    # --- Prompt password ------------------------------------------------------
    local pass=""
    _appadmin_prompt_password pass "New"

    # --- Dispatch -------------------------------------------------------------
    case "$app" in
        pma) _appadmin_add_pma "$user" "$pass" ;;
        fb)  _appadmin_add_fb  "$user" "$pass" ;;
    esac
    pass=""
}
