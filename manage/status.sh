#!/bin/bash
###############################################################################
#  manage/status.sh — Show server status (services, disk, memory, SSL, modules)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
###############################################################################

cmd_status() {
    section "Service Status"

    local services=("nginx" "mariadb" "php${PHP_VERSION}-fpm" "redis-server" "fail2ban")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${C_GRN}running${C_RST}  ${svc}"
        else
            echo -e "  ${C_RED}stopped${C_RST}  ${svc}"
        fi
    done

    section "Disk Usage"
    df -h / | awk 'NR==2 {printf "  Total: %s  Used: %s  Free: %s  (%s)\n", $2, $3, $4, $5}'

    section "Memory"
    free -h | awk '
        /^Mem:/  { printf "  RAM  : %s total, %s used, %s free\n", $2, $3, $4 }
        /^Swap:/ { printf "  Swap : %s total, %s used, %s free\n", $2, $3, $4 }
    '

    section "SSL Certificates"
    local found=0
    local conf
    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "000-default" ]] && continue
        found=$((found + 1))

        local cert="/etc/letsencrypt/live/${name}/fullchain.pem"
        if [[ -f "$cert" ]]; then
            local expiry days_left
            expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2 || true)
            if [[ -n "$expiry" ]]; then
                local exp_epoch now_epoch
                exp_epoch=$(date -d "$expiry" +%s 2>/dev/null || true)
                now_epoch=$(date +%s)
                if [[ -n "$exp_epoch" ]]; then
                    days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                    local color="$C_GRN"
                    [[ $days_left -le 30 ]] && color="$C_YLW"
                    [[ $days_left -le 7 ]] && color="$C_RED"
                    echo -e "  ${name}: expires ${expiry} (${color}${days_left} days${C_RST})"
                else
                    echo "  ${name}: expires ${expiry}"
                fi
            fi
        else
            echo -e "  ${name}: ${C_YLW}No SSL certificate${C_RST}"
        fi
    done
    [[ $found -eq 0 ]] && info "No sites configured."

    section "Installed Modules"
    state_list
}
