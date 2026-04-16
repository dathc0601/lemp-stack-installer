#!/bin/bash
###############################################################################
#  modules/90-swap.sh — Swap file, conditional on low RAM (NEW)
#
#  Creates a swap file only if total RAM < 4096 MB.
#  This is a new module not present in v2.0.1.
###############################################################################

module_swap_describe() {
    echo "Swap file — conditional on RAM < 4GB"
}

module_swap_check() {
    return 1
}

module_swap_install() {
    # TODO: implement — new module, conditional on: free -m total < 4096
    return 0
}
