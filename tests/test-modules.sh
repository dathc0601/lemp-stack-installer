#!/bin/bash
###############################################################################
#  test-modules.sh — Verify all modules define the required contract functions
#
#  Usage: bash tests/test-modules.sh
#  Returns: 0 if all modules pass, 1 if any fail
#
#  Module naming convention:
#    filename  NN-foo-bar.sh  →  strip numeric prefix  →  foo-bar
#    hyphens to underscores   →  foo_bar
#    expected functions: module_foo_bar_describe, module_foo_bar_check,
#                        module_foo_bar_install
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

passed=0
failed=0

# Source lib files first (modules may reference lib functions in future)
for lib in "${SCRIPT_DIR}"/lib/*.sh; do
    [[ -f "$lib" ]] || continue
    # shellcheck source=/dev/null
    source "$lib"
done

for mod_file in "${SCRIPT_DIR}"/modules/*.sh; do
    [[ -f "$mod_file" ]] || continue
    # shellcheck source=/dev/null
    source "$mod_file"

    # Extract module name: "10-base.sh" -> "base"
    #                      "85-unattended-upgrades.sh" -> "unattended_upgrades"
    basename_no_ext="$(basename "$mod_file" .sh)"
    mod_name="${basename_no_ext#*-}"    # strip numeric prefix and first hyphen
    mod_name="${mod_name//-/_}"         # remaining hyphens to underscores

    ok=true
    for func in "module_${mod_name}_describe" "module_${mod_name}_check" "module_${mod_name}_install"; do
        if ! declare -f "$func" &>/dev/null; then
            echo "FAIL: ${mod_file} missing function: ${func}"
            ok=false
        fi
    done

    if $ok; then
        echo "PASS: ${basename_no_ext}"
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
done

echo ""
echo "Results: ${passed} passed, ${failed} failed"
[[ $failed -eq 0 ]]
