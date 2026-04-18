#!/bin/bash
###############################################################################
#  lib/credentials.sh — Credentials file management
#
#  Pure function definitions — no side effects on source.
#  Depends on: lib/core.sh (constants, logging)
#
#  Credentials are written to /root/.server-credentials with mode 600.
#  Never echoed to stdout — summary only prints the file path.
###############################################################################

# =============================================================================
#  CREDENTIALS FILE PRIMITIVES
# =============================================================================

# Initialize the credentials file with a header
init_credentials_file() {
    cat > "$CREDENTIALS_FILE" <<EOF
###############################################################################
#  SERVER CREDENTIALS — KEEP THIS FILE PRIVATE
#  Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
#  Host:      $(hostname -f 2>/dev/null || hostname)
###############################################################################
EOF
    chmod 600 "$CREDENTIALS_FILE"
    log "Credentials file initialized: $CREDENTIALS_FILE (mode 600)"
}

# Append a line to the credentials file
cred_write() {
    local content="$1"
    echo "$content" >> "$CREDENTIALS_FILE"
}

# =============================================================================
#  CREDENTIAL SECTIONS
# =============================================================================

# Write the main service credentials (MariaDB, phpMyAdmin, File Browser)
# Called after all modules have been installed.
write_main_credentials() {
    cred_write ""
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  MARIADB"
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  Root user : root"
    cred_write "  Root pass : ${MYSQL_ROOT_PASS}"

    cred_write ""
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  PHPMYADMIN"
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  URL path  : ${PMA_PATH}"
    cred_write "  Login     : root  /  (see MariaDB above)"
    cred_write "  Example   : https://<your-domain>${PMA_PATH}"

    cred_write ""
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  PHPMYADMIN — HTTP BASIC AUTH (pre-login gate)"
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  File      : ${PMA_HTPASSWD_FILE}"
    cred_write "  Username  : ${PMA_AUTH_USER}"
    cred_write "  Password  : ${PMA_AUTH_PASS}"
    cred_write "  Note      : Browser prompts for this BEFORE phpMyAdmin's"
    cred_write "              login screen. MySQL credentials above are the"
    cred_write "              second gate. Manage via 'lemp-manage appadmin-*'."

    cred_write ""
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  FILE BROWSER"
    cred_write "═══════════════════════════════════════════════════════════"
    cred_write "  URL path  : ${FB_PATH}"
    cred_write "  Username  : ${FB_USER}"
    cred_write "  Password  : ${FB_PASS}"
    cred_write "  Example   : https://<your-domain>${FB_PATH}"
    cred_write "  Root dir  : ${WEB_ROOT_BASE}"
}
