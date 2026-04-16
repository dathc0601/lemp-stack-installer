#!/bin/bash
###############################################################################
#  manage/list-sites.sh — List all configured domains and their status
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
###############################################################################

cmd_list_sites() {
    section "Configured Sites"

    local count=0
    local conf
    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "000-default" ]] && continue

        count=$((count + 1))

        # Extract root directive from the vhost config
        local web_root
        web_root=$(grep -oP '^\s+root\s+\K\S+' "$conf" | head -1 | tr -d ';' || true)

        # Check SSL status
        local ssl="No"
        if grep -q "listen 443" "$conf" 2>/dev/null || grep -q "Certbot" "$conf" 2>/dev/null; then
            ssl="Yes"
        fi

        # Disk usage of web root
        local disk_usage="N/A"
        if [[ -n "$web_root" ]] && [[ -d "$web_root" ]]; then
            disk_usage=$(du -sh "$web_root" 2>/dev/null | awk '{print $1}' || true)
        fi

        echo "  ${name}"
        echo "    Root : ${web_root:-unknown}"
        echo "    SSL  : ${ssl}"
        echo "    Size : ${disk_usage}"
        echo ""
    done

    if [[ $count -eq 0 ]]; then
        info "No sites configured."
    else
        info "${count} site(s) configured."
    fi
}
