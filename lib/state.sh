#!/bin/bash
###############################################################################
#  lib/state.sh — Installation state tracking (idempotency/rollback)
#
#  State file: /var/lib/server-setup/state
#  Format: one line per installed module — "name version timestamp"
#
#  Provides:
#   - state_mark_installed()   — record a module as installed
#   - state_is_installed()     — check if a module is already installed (return 0/1)
#   - state_get_version()      — get installed version of a module
#   - state_list()             — list all installed modules
#
#  Design: flat file, no JSON dependencies. Under 100 lines.
###############################################################################
