#!/bin/bash
###############################################################################
#  lib/core.sh — Core constants, colors, logging, traps, FD setup
#
#  Provides:
#   - Color constants (C_RED, C_GRN, C_YLW, C_BLU, C_RST)
#   - Path constants (LOG_FILE, CREDENTIALS_FILE, WEB_ROOT_BASE, etc.)
#   - Version constants (PHP_VERSION, NODE_MAJOR, MARIADB_SERIES)
#   - PHP tuning constants
#   - Nginx path constants
#   - File Browser / phpMyAdmin constants
#   - Runtime globals (MYSQL_ROOT_PASS, FB_PASS, DOMAINS, etc.)
#   - Logging: log(), info(), warn(), err(), section()
#   - FD 3/4 setup for tee-safe error output
#   - ERR and EXIT traps
#   - command_exists()
#   - run_module() dispatcher
###############################################################################
