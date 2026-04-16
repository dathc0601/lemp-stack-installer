#!/bin/bash
###############################################################################
#  modules/75-filebrowser.sh — File Browser with randomized URL path
#
#  Installs File Browser, creates systemd unit, configures JSON config.
#  URL path randomized (e.g. /files-d9e8f7g6). Nginx snippet for vhosts.
#  Runs as root via systemd (required for web root file management).
###############################################################################

module_filebrowser_describe() {
    echo "File Browser — randomized URL path"
}

module_filebrowser_check() {
    return 1
}

module_filebrowser_install() {
    # TODO: migrate from server-setup.sh install_filebrowser()
    return 0
}
