#!/bin/bash
###############################################################################
#  lib/credentials.sh — Credentials file management
#
#  Credentials are written to /root/.server-credentials with mode 600.
#  Never echoed to stdout — summary only prints the file path.
#
#  Provides:
#   - init_credentials_file()     — create credentials file with header
#   - cred_write()                — append content to credentials file
#   - write_main_credentials()    — write MariaDB/PMA/FB credential sections
###############################################################################
