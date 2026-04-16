#!/bin/bash
###############################################################################
#  modules/95-domains.sh — Nginx vhost creation for configured domains
#
#  Creates per-domain vhost configs, web roots, placeholder HTML.
#  Creates default catch-all vhost (returns 444).
#  Includes security headers, rate limiting, admin tool snippets.
###############################################################################

module_domains_describe() {
    echo "Domain vhosts — nginx configuration"
}

module_domains_check() {
    return 1
}

module_domains_install() {
    # TODO: migrate from server-setup.sh configure_domains(), create_domain_vhost(),
    #       create_default_vhost(), cleanup_default_nginx_files()
    return 0
}
