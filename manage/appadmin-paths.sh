#!/bin/bash
###############################################################################
#  manage/appadmin-paths.sh — Rotate phpMyAdmin + File Browser URL suffixes
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage appadmin-paths
#
#  Our equivalent of LarVPS's "Doi Port Admin". Since we use path-based
#  obscurity, rotation regenerates /pma-<hex> and /files-<hex>, rewrites both
#  nginx snippets + filebrowser.json baseURL, reloads nginx, restarts
#  filebrowser, and updates /root/.server-credentials.
###############################################################################

readonly _APPADMIN_PMA_SNIPPET="${NGINX_SNIPPETS_DIR}/phpmyadmin.conf"
readonly _APPADMIN_FB_SNIPPET="${NGINX_SNIPPETS_DIR}/filebrowser.conf"
readonly _APPADMIN_FB_CONFIG="${FB_CONFIG_DIR}/filebrowser.json"

_appadmin_detect_current_path() {
    local snippet="$1"
    [[ -f "$snippet" ]] || return 1
    grep -m1 '^location ' "$snippet" | awk '{print $2}' || true
}

# Rewrite a `URL path  : …` line inside a named section of the credentials file.
# Section matches start at the capitalized section title line and end at the
# next `═` rule, so the two URL-path lines (PMA vs FB) don't collide.
_appadmin_cred_update_path() {
    local section_title="$1" new_path="$2"
    [[ -f "$CREDENTIALS_FILE" ]] || { warn "Credentials file missing — skipping update."; return 0; }
    sed -i "/^  ${section_title}$/,/^═/ s|^  URL path  : .*|  URL path  : ${new_path}|" \
        "$CREDENTIALS_FILE" \
        || warn "Failed to update ${section_title} URL path in ${CREDENTIALS_FILE}."
}

cmd_appadmin_paths() {
    command_exists nginx        || err "nginx not installed."
    command_exists filebrowser  || err "filebrowser CLI not installed."
    [[ -f "$_APPADMIN_PMA_SNIPPET" ]] || err "Missing: ${_APPADMIN_PMA_SNIPPET}"
    [[ -f "$_APPADMIN_FB_SNIPPET"  ]] || err "Missing: ${_APPADMIN_FB_SNIPPET}"
    [[ -f "$_APPADMIN_FB_CONFIG"   ]] || err "Missing: ${_APPADMIN_FB_CONFIG}"

    _detect_nginx_user  # for any downstream chown — PMA snippet owner stays root

    section "Rotate admin URL paths"

    local current_pma current_fb
    current_pma=$(_appadmin_detect_current_path "$_APPADMIN_PMA_SNIPPET") \
        || err "Could not read current PMA path."
    current_fb=$(_appadmin_detect_current_path "$_APPADMIN_FB_SNIPPET") \
        || err "Could not read current File Browser path."

    local new_pma new_fb
    new_pma="/pma-$(generate_url_token)"
    new_fb="/files-$(generate_url_token)"

    info "phpMyAdmin : ${current_pma} → ${new_pma}"
    info "File Brwsr : ${current_fb} → ${new_fb}"
    warn "File Browser will restart (brief outage, seconds)."
    echo ""
    confirm "Proceed with path rotation?" "N" || { info "Aborted."; return 0; }

    # --- Backups --------------------------------------------------------------
    local ts backup_dir
    ts=$(date -u +%Y%m%d%H%M%S)
    backup_dir="$(dirname "$_APPADMIN_PMA_SNIPPET")"
    cp -a "$_APPADMIN_PMA_SNIPPET" "${_APPADMIN_PMA_SNIPPET}.bak-${ts}"
    cp -a "$_APPADMIN_FB_SNIPPET"  "${_APPADMIN_FB_SNIPPET}.bak-${ts}"
    cp -a "$_APPADMIN_FB_CONFIG"   "${_APPADMIN_FB_CONFIG}.bak-${ts}"

    _appadmin_restore() {
        info "Restoring snippets + filebrowser config from ${ts} backups..."
        mv -f "${_APPADMIN_PMA_SNIPPET}.bak-${ts}" "$_APPADMIN_PMA_SNIPPET" 2>/dev/null || true
        mv -f "${_APPADMIN_FB_SNIPPET}.bak-${ts}"  "$_APPADMIN_FB_SNIPPET"  2>/dev/null || true
        mv -f "${_APPADMIN_FB_CONFIG}.bak-${ts}"   "$_APPADMIN_FB_CONFIG"   2>/dev/null || true
    }

    # --- Render new PMA snippet ----------------------------------------------
    local tmp
    tmp=$(mktemp)
    render_template "nginx-phpmyadmin.conf.tpl" \
        "PMA_PATH" "$new_pma" \
        "PMA_DIR" "$PMA_DIR" \
        "PHP_VERSION" "$PHP_VERSION" \
        "PHP_MAX_EXEC_TIME" "$PHP_MAX_EXEC_TIME" \
        "PMA_HTPASSWD_FILE" "$PMA_HTPASSWD_FILE" \
        > "$tmp"
    mv "$tmp" "$_APPADMIN_PMA_SNIPPET"

    # --- Render new FB snippet -----------------------------------------------
    tmp=$(mktemp)
    render_template "nginx-filebrowser.conf.tpl" \
        "FB_PATH" "$new_fb" \
        "FB_PORT" "$FB_PORT" \
        > "$tmp"
    mv "$tmp" "$_APPADMIN_FB_SNIPPET"

    # --- Update filebrowser.json baseURL --------------------------------------
    # Simple string swap — `baseURL` is on its own line in our install-time JSON.
    local escaped_old escaped_new
    escaped_old=$(printf '%s' "$current_fb" | sed 's|/|\\/|g')
    escaped_new=$(printf '%s' "$new_fb"     | sed 's|/|\\/|g')
    if ! sed -i "s|\"baseURL\":[[:space:]]*\"${escaped_old}\"|\"baseURL\": \"${escaped_new}\"|" \
            "$_APPADMIN_FB_CONFIG"; then
        _appadmin_restore
        err "sed failed to update baseURL in ${_APPADMIN_FB_CONFIG}."
    fi

    # --- Validate nginx config ------------------------------------------------
    if ! nginx -t >/dev/null 2>&1; then
        _appadmin_restore
        err "nginx -t failed after rotation — originals restored."
    fi

    # --- Reload nginx, restart filebrowser ------------------------------------
    if ! systemctl reload nginx; then
        _appadmin_restore
        err "nginx reload failed — originals restored (nginx likely still serves old paths)."
    fi
    if ! systemctl restart filebrowser; then
        warn "filebrowser restart failed — check: journalctl -u filebrowser"
    fi

    # --- Update credentials file ---------------------------------------------
    _appadmin_cred_update_path "PHPMYADMIN"   "$new_pma"
    _appadmin_cred_update_path "FILE BROWSER" "$new_fb"

    # --- Cleanup backups on success ------------------------------------------
    rm -f "${_APPADMIN_PMA_SNIPPET}.bak-${ts}" \
          "${_APPADMIN_FB_SNIPPET}.bak-${ts}" \
          "${_APPADMIN_FB_CONFIG}.bak-${ts}"

    log "Admin paths rotated: PMA ${new_pma}, FB ${new_fb}"
    info "New URLs recorded in ${CREDENTIALS_FILE}."
}
