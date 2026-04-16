#!/bin/bash
###############################################################################
#  manage/wp-install.sh — Install WordPress on a configured domain
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage wp-install <domain>
#  Downloads WordPress, configures wp-config.php with the domain's DB creds.
#  Uses WP-CLI if available, falls back to curl + manual config.
###############################################################################

cmd_wp_install() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage wp-install <domain>"

    _domain_exists "$domain" || err "No vhost found for '${domain}'. Run 'lemp-manage add-domain ${domain}' first."

    local web_root="${WEB_ROOT_BASE}/${domain}"
    [[ -d "$web_root" ]] || err "Web root not found: ${web_root}"
    [[ ! -f "${web_root}/wp-config.php" ]] || err "WordPress already installed at ${web_root}/wp-config.php"

    _detect_nginx_user
    _read_mysql_root_pass

    section "Installing WordPress: ${domain}"

    # Read domain DB credentials
    local db_name db_user db_pass
    db_name=$(_domain_db_name "$domain")
    db_user="${db_name}_user"
    db_pass=$(_read_domain_db_pass "$domain")
    [[ -n "$db_pass" ]] || err "Cannot find DB password for '${domain}' in ${CREDENTIALS_FILE}. Was the domain added via lemp-manage or the installer?"

    # Download WordPress
    if command_exists wp; then
        _wp_install_via_cli "$web_root" "$db_name" "$db_user" "$db_pass"
    else
        _wp_install_via_curl "$web_root" "$db_name" "$db_user" "$db_pass"
    fi

    # Set ownership
    chown -R "${NGINX_USER}:${NGINX_USER}" "$web_root"

    log "WordPress installed at ${web_root}"
    echo ""
    info "Complete the setup at:"
    echo "  http://${domain}/wp-admin/install.php"
    echo ""
    info "Database credentials:"
    echo "  DB name : ${db_name}"
    echo "  DB user : ${db_user}"
    echo "  DB pass : (see ${CREDENTIALS_FILE})"
    echo ""
}

# --- Private helpers --------------------------------------------------------

_wp_install_via_cli() {
    local web_root="$1" db_name="$2" db_user="$3" db_pass="$4"

    info "Using WP-CLI..."
    wp core download --path="$web_root" --allow-root --quiet
    wp config create \
        --path="$web_root" \
        --dbname="$db_name" \
        --dbuser="$db_user" \
        --dbpass="$db_pass" \
        --dbhost="localhost" \
        --allow-root --quiet
}

_wp_install_via_curl() {
    local web_root="$1" db_name="$2" db_user="$3" db_pass="$4"

    info "Downloading WordPress..."
    local wp_tarball="/tmp/wordpress-latest.tar.gz"
    curl -fsSL "https://wordpress.org/latest.tar.gz" -o "$wp_tarball"
    tar -xzf "$wp_tarball" -C /tmp

    # Remove placeholder, move WordPress files into web root
    rm -f "${web_root}/index.html"
    cp -a /tmp/wordpress/. "$web_root/"
    rm -rf /tmp/wordpress "$wp_tarball"

    # Generate wp-config.php from the sample
    local wp_config="${web_root}/wp-config.php"
    cp "${web_root}/wp-config-sample.php" "$wp_config"

    # Replace DB placeholders
    sed -i "s/database_name_here/${db_name}/" "$wp_config"
    sed -i "s/username_here/${db_user}/" "$wp_config"
    sed -i "s/password_here/${db_pass}/" "$wp_config"

    # Fetch fresh salt keys from the WordPress API
    _wp_replace_salts "$wp_config"
}

_wp_replace_salts() {
    local wp_config="$1"

    local salts
    salts=$(curl -fsSL "https://api.wordpress.org/secret-key/1.1/salt/" 2>/dev/null || true)

    if [[ -z "$salts" ]]; then
        warn "Could not fetch WordPress salts — using defaults (change them manually)."
        return
    fi

    # Remove existing salt placeholder lines
    local salt_keys=("AUTH_KEY" "SECURE_AUTH_KEY" "LOGGED_IN_KEY" "NONCE_KEY"
                     "AUTH_SALT" "SECURE_AUTH_SALT" "LOGGED_IN_SALT" "NONCE_SALT")
    for key in "${salt_keys[@]}"; do
        sed -i "/define( '${key}'/d" "$wp_config"
    done

    # Insert fresh salts before the "stop editing" marker
    local marker="That's all, stop editing"
    awk -v salts="$salts" -v marker="$marker" \
        '{ if (index($0, marker)) print salts; print }' "$wp_config" > "${wp_config}.tmp"
    mv "${wp_config}.tmp" "$wp_config"

    log "WordPress salts configured."
}
