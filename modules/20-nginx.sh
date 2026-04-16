#!/bin/bash
###############################################################################
#  modules/20-nginx.sh — Nginx mainline from official repo
#
#  Installs nginx from nginx.org (not Ubuntu distro package).
#  Detects nginx user dynamically from nginx.conf.
#  Creates snippets directory, enables service.
###############################################################################

module_nginx_describe() {
    echo "Nginx — mainline from nginx.org"
}

module_nginx_check() {
    return 1
}

module_nginx_install() {
    # TODO: migrate from server-setup.sh install_nginx(), detect_nginx_user()
    return 0
}
