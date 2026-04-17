#!/bin/bash
###############################################################################
#  manage/ssl-list.sh — List SSL certificates for all configured domains
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage ssl-list
#
#  Enumerates vhosts in /etc/nginx/conf.d/ (minus 000-default), checks for
#  a matching /etc/letsencrypt/live/<domain>/fullchain.pem, and prints
#  expiry + days-left for each. Colors days-left yellow at <=30, red at <=7.
###############################################################################

cmd_ssl_list() {
    section "SSL Certificates"

    local count=0 with_ssl=0 without_ssl=0
    local conf name

    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        name=$(basename "$conf" .conf)
        [[ "$name" == "000-default" ]] && continue
        count=$((count + 1))

        local cert="/etc/letsencrypt/live/${name}/fullchain.pem"
        if [[ -f "$cert" ]]; then
            with_ssl=$((with_ssl + 1))
            local expiry=""
            expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2 || true)
            if [[ -n "$expiry" ]]; then
                local exp_epoch now_epoch days_left color
                exp_epoch=$(date -d "$expiry" +%s 2>/dev/null || true)
                now_epoch=$(date +%s)
                if [[ -n "$exp_epoch" ]]; then
                    days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                    color="$C_GRN"
                    [[ $days_left -le 30 ]] && color="$C_YLW"
                    [[ $days_left -le 7 ]]  && color="$C_RED"
                    echo -e "  ${C_GRN}✓${C_RST} ${name}"
                    echo -e "      Expires: ${expiry} (${color}${days_left} days${C_RST})"
                else
                    echo -e "  ${C_GRN}✓${C_RST} ${name}"
                    echo "      Expires: ${expiry}"
                fi
            else
                echo -e "  ${C_GRN}✓${C_RST} ${name}"
                echo -e "      ${C_YLW}Could not read certificate expiry${C_RST}"
            fi
        else
            without_ssl=$((without_ssl + 1))
            echo -e "  ${C_YLW}✗${C_RST} ${name} — No SSL"
        fi
        echo ""
    done

    if [[ $count -eq 0 ]]; then
        info "No sites configured."
    else
        info "${count} site(s): ${with_ssl} with SSL, ${without_ssl} without."
    fi
}
