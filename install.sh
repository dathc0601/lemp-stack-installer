#!/bin/bash
###############################################################################
#  LEMP Stack Installer — Entry Point
#  Sources lib/ and modules/, then calls main().
#
#  Module naming convention:
#    filename  NN-foo-bar.sh  →  strip prefix  →  foo-bar
#    hyphens to underscores   →  foo_bar
#    functions: module_foo_bar_describe(), module_foo_bar_check(),
#               module_foo_bar_install()
###############################################################################

set -Eeuo pipefail

readonly INSTALLER_VERSION="2.1.0-dev"
readonly INSTALLER_NAME="LEMP Stack Installer"

# Resolve the directory this script lives in (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# --- Source library files (alphabetical: core.sh loads first) ---
for _lib in "${SCRIPT_DIR}"/lib/*.sh; do
    [[ -f "$_lib" ]] || continue
    # shellcheck source=/dev/null
    source "$_lib"
done
unset _lib

# --- Source module files (sorted by numeric prefix) ---
for _mod in "${SCRIPT_DIR}"/modules/*.sh; do
    [[ -f "$_mod" ]] || continue
    # shellcheck source=/dev/null
    source "$_mod"
done
unset _mod

# --- Main ---
main() {
    echo ""
    echo "  ${INSTALLER_NAME} v${INSTALLER_VERSION}"
    echo ""
    # TODO: preflight, input, module dispatch
}

main "$@"
