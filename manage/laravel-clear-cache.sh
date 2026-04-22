#!/bin/bash
###############################################################################
#  manage/laravel-clear-cache.sh — Clear Laravel caches (and file sessions)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage laravel-clear-cache <domain>
#
#  Runs `php artisan optimize:clear` (flushes cache, compiled views, route
#  cache, config cache, and compiled classes), then wipes the file-driver
#  session store at storage/framework/sessions/. Harmless no-op on domains
#  using the database/redis session driver.
#
#  Refuses to run on non-Laravel domains (WordPress/raw).
###############################################################################

cmd_laravel_clear_cache() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || err "Usage: lemp-manage laravel-clear-cache <domain>"

    _domain_exists "$domain" \
        || err "No vhost found for '${domain}'. Run 'lemp-manage add-domain ${domain}' first."

    local site_root="${WEB_ROOT_BASE}/${domain}"
    [[ -d "$site_root" ]] || err "Web root not found: ${site_root}"

    # --- App-type gate -------------------------------------------------------
    local kind
    kind=$(_app_detect "$domain")
    [[ "$kind" == "laravel" ]] \
        || err "Not a Laravel app at ${site_root} (detected: ${kind}). This command only targets Laravel installations."

    command_exists php \
        || err "php not found. Re-run the installer."

    section "Clearing Laravel caches: ${domain}"

    # --- Step 1: optimize:clear ---------------------------------------------
    # Single command that drains cache, view, route, config, and compiled.
    # Preferred over calling each :clear variant individually.
    info "Running php artisan optimize:clear..."
    ( cd "$site_root" && php artisan optimize:clear ) \
        || err "php artisan optimize:clear failed. Run manually in ${site_root}."

    # --- Step 2: wipe file-driver sessions ----------------------------------
    # Default session driver in Laravel's .env.example is 'file', which stores
    # sessions at storage/framework/sessions/*. Idempotent — no-op on empty
    # dir or database/redis drivers (the rm simply matches nothing).
    local session_dir="${site_root}/storage/framework/sessions"
    if [[ -d "$session_dir" ]]; then
        info "Wiping file-driver sessions..."
        # shellcheck disable=SC2115
        rm -f "${session_dir}"/* 2>/dev/null || true
    fi

    log "Caches cleared on ${domain}."
}
