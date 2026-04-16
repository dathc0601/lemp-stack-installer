#!/bin/bash
###############################################################################
#  lib/preflight.sh — Pre-flight checks
#
#  Provides:
#   - preflight_checks()    — root check, OS detection, SSH port, log init
#   - detect_ssh_port()     — sshd_config + drop-ins + ss fallback
#
#  SSH port detection strategy:
#   1. Parse /etc/ssh/sshd_config
#   2. Parse /etc/ssh/sshd_config.d/*.conf (Ubuntu 24.04 drop-ins)
#   3. Live socket lookup via ss
#   4. Fall back to port 22
#  Every grep pipeline ends in || true to survive set -e + pipefail.
###############################################################################
