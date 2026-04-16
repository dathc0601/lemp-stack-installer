#!/bin/bash
###############################################################################
#  lib/utils.sh — Utility helpers
#
#  Provides:
#   - generate_password()     — URL-safe random password of N chars
#   - generate_url_token()    — short hex token for URL paths
#   - confirm()               — yes/no prompt with default
#   - apt_install()           — non-interactive apt-get install
#   - apt_update()            — non-interactive apt-get update
#   - apt_upgrade()           — non-interactive apt-get upgrade
#   - render_template()       — {{PLACEHOLDER}} substitution from templates/
###############################################################################
