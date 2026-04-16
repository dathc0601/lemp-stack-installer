#!/bin/bash
###############################################################################
#  lib/input.sh — Interactive user prompts
#
#  Provides:
#   - collect_user_input()          — orchestrates all prompts + summary
#   - prompt_mysql_password()       — MariaDB root password (generate or manual)
#   - prompt_filebrowser_password() — File Browser admin password
#   - prompt_domains()              — domain list input with validation
#
#  Password rules:
#   - Empty input → auto-generate 24+ char random password
#   - Manual input → minimum 12 chars + confirmation
#   - Never echo passwords to stdout
###############################################################################
