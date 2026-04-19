#!/bin/bash
###############################################################################
#  manage/swap-remove.sh — Swapoff + delete /swapfile + clean fstab entry
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage swap-remove
#
#  Operates only on /swapfile (the path owned by the installer and swap-add).
#  Partition swaps (/dev/sdX) are left untouched — those are provisioning
#  decisions that shouldn't be undone from a TUI.
###############################################################################

cmd_swap_remove() {
    section "Remove swap"

    local on_disk=0 in_fstab=0 active=0
    [[ -e /swapfile ]] && on_disk=1
    _swap_fstab_has /swapfile && in_fstab=1
    if swapon --show --noheadings 2>/dev/null | awk '{print $1}' | grep -qx /swapfile; then
        active=1
    fi

    if [[ $on_disk -eq 0 && $in_fstab -eq 0 ]]; then
        info "No /swapfile to remove."
        return 0
    fi

    # --- Show current state --------------------------------------------------
    if [[ $active -eq 1 ]]; then
        local size used used_mb avail_mb
        size=$(swapon --show --noheadings 2>/dev/null | awk '$1=="/swapfile"{print $3}' || echo "?")
        used=$(swapon --show --noheadings 2>/dev/null | awk '$1=="/swapfile"{print $4}' || echo "?")
        info "/swapfile is active (size ${size}, used ${used})."

        # Warn when used swap would not fit in available RAM.
        used_mb=$(free -m | awk '/^Swap:/ {print $3}' 2>/dev/null || echo 0)
        avail_mb=$(free -m | awk '/^Mem:/ {print $7}' 2>/dev/null || echo 0)
        if [[ "$used_mb" -gt 0 && "$avail_mb" -gt 0 && "$used_mb" -gt "$avail_mb" ]]; then
            warn "Used swap (${used_mb}M) > available RAM (${avail_mb}M). Removing may trigger OOM."
        fi
    elif [[ $on_disk -eq 1 ]]; then
        local size
        size=$(du -h /swapfile 2>/dev/null | awk '{print $1}' || echo "?")
        info "/swapfile is on disk (${size}) but inactive."
    fi

    # --- Gate ----------------------------------------------------------------
    confirm "Remove /swapfile and its fstab entry?" "N" \
        || { info "Aborted."; return 0; }

    # --- Swapoff (active only) ----------------------------------------------
    if [[ $active -eq 1 ]]; then
        swapoff /swapfile \
            || err "swapoff failed (insufficient free memory?). Aborting — swap file preserved."
    fi

    # --- Delete --------------------------------------------------------------
    [[ $on_disk -eq 1 ]] && rm -f /swapfile

    # --- Clean fstab ---------------------------------------------------------
    [[ $in_fstab -eq 1 ]] && _swap_fstab_remove /swapfile

    log "Swap removed: /swapfile deleted, fstab entry cleaned."
}
