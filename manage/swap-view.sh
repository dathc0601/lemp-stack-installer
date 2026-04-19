#!/bin/bash
###############################################################################
#  manage/swap-view.sh — Detailed swap state (swapon + fstab + sysctl + free)
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage swap-view
#
#  Read-only; prints everything useful for diagnosing swap behavior in one go.
###############################################################################

cmd_swap_view() {
    section "Swap status"

    # --- Active swaps (kernel view) ------------------------------------------
    echo ""
    echo "  Active swaps (swapon --show):"
    local active
    active=$(swapon --show 2>/dev/null || true)
    if [[ -z "$active" ]]; then
        echo "    (none)"
    else
        echo "$active" | sed 's/^/    /'
    fi
    echo ""

    # --- /swapfile on disk ---------------------------------------------------
    if [[ -e /swapfile ]]; then
        local size mode
        size=$(du -h /swapfile 2>/dev/null | awk '{print $1}' || echo "?")
        mode=$(stat -c '%a' /swapfile 2>/dev/null || echo "?")
        echo "  /swapfile on disk  : ${size} (mode ${mode})"
    else
        echo "  /swapfile on disk  : (not present)"
    fi

    # --- fstab entry ---------------------------------------------------------
    local fstab_line
    fstab_line=$(grep -E "^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]" /etc/fstab 2>/dev/null || true)
    if [[ -n "$fstab_line" ]]; then
        echo "  /etc/fstab entry   : ${fstab_line}"
    else
        echo "  /etc/fstab entry   : (not configured)"
    fi
    echo ""

    # --- Kernel tunables -----------------------------------------------------
    local swappiness_live cache_live swappiness_conf
    swappiness_live=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "?")
    cache_live=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "?")
    swappiness_conf=$(grep -E '^\s*vm\.swappiness\s*=' /etc/sysctl.conf 2>/dev/null \
        | tail -1 | awk -F= '{print $2}' | tr -d ' ' || true)
    [[ -n "$swappiness_conf" ]] || swappiness_conf="(unset)"

    echo "  Kernel tunables:"
    echo "    vm.swappiness         = ${swappiness_live} (sysctl.conf: ${swappiness_conf})"
    echo "    vm.vfs_cache_pressure = ${cache_live}"
    echo ""

    # --- Memory summary ------------------------------------------------------
    echo "  Memory:"
    free -h | sed 's/^/    /'
}
