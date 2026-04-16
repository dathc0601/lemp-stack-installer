#!/bin/bash
###############################################################################
#  modules/90-swap.sh — Swap file, conditional on low RAM (NEW)
#
#  Creates a swap file only if total RAM < 4096 MB.
#  Swap size = total RAM (common recommendation for servers < 4GB).
#  Sets swappiness to 10 (prefer RAM, use swap only under pressure).
#
#  Depends on: lib/core.sh (logging)
#              lib/state.sh (state_mark_installed)
###############################################################################

module_swap_describe() {
    echo "Swap file — conditional on RAM < 4GB"
}

module_swap_check() {
    # Skip if swap already exists (from us or otherwise)
    [[ $(swapon --show --noheadings 2>/dev/null | wc -l) -gt 0 ]] && state_is_installed "swap"
}

module_swap_install() {
    section "Checking swap requirements"

    local total_mb
    total_mb=$(free -m | awk '/^Mem:/ {print $2}')

    if [[ "$total_mb" -ge 4096 ]]; then
        info "RAM is ${total_mb}MB (>= 4GB) — swap not needed."
        state_mark_installed "swap"
        return
    fi

    if [[ $(swapon --show --noheadings 2>/dev/null | wc -l) -gt 0 ]]; then
        info "Swap already active — skipping."
        state_mark_installed "swap"
        return
    fi

    _swap_create "${total_mb}"
    state_mark_installed "swap"
}

# --- Private helpers --------------------------------------------------------

_swap_create() {
    local size_mb="$1"
    local swapfile="/swapfile"

    info "Creating ${size_mb}MB swap file..."
    fallocate -l "${size_mb}M" "$swapfile"
    chmod 600 "$swapfile"
    mkswap "$swapfile"
    swapon "$swapfile"

    # Make persistent across reboots
    if ! grep -q "$swapfile" /etc/fstab; then
        echo "${swapfile} none swap sw 0 0" >> /etc/fstab
    fi

    # Set swappiness to 10 (prefer RAM, use swap only under memory pressure)
    sysctl vm.swappiness=10
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi

    log "Swap enabled: ${size_mb}MB (swappiness=10)"
}
