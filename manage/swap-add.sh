#!/bin/bash
###############################################################################
#  manage/swap-add.sh — Create /swapfile, persist in fstab, set swappiness=10
#  Called by manage.sh dispatcher — inherits lib/ and set -Eeuo pipefail.
#
#  Usage: lemp-manage swap-add [size]
#    size: integer MB (e.g. 2048), or with suffix M/G (e.g. 2G, 1024M).
#
#  Refuses to clobber an already-active /swapfile — use swap-remove first
#  if you want to resize. Falls back to `dd` if `fallocate` is unavailable.
###############################################################################

cmd_swap_add() {
    local raw_size="${1:-}"

    section "Add swap"

    # --- Refuse if /swapfile is already active -------------------------------
    if swapon --show --noheadings 2>/dev/null | awk '{print $1}' | grep -qx /swapfile; then
        local cur_size
        cur_size=$(swapon --show --noheadings 2>/dev/null | awk '$1=="/swapfile"{print $3}' || echo "?")
        info "/swapfile already active (${cur_size}). Use 'swap-remove' first to resize."
        return 0
    fi

    # --- Stale on disk but not active? ---------------------------------------
    if [[ -e /swapfile ]]; then
        local stale_size
        stale_size=$(du -h /swapfile 2>/dev/null | awk '{print $1}' || echo "?")
        warn "/swapfile exists on disk (${stale_size}) but is not active."
        confirm "Delete and recreate?" "N" || { info "Aborted."; return 0; }
        rm -f /swapfile
    fi

    # --- Size prompt ---------------------------------------------------------
    local ram_mb suggested
    ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ "$ram_mb" -ge 4096 ]]; then
        suggested=2048
    else
        suggested="$ram_mb"
    fi

    if [[ -z "$raw_size" ]]; then
        read -rp "─// Swap size (e.g. 1024, 2G) [default: ${suggested}]: " raw_size
        raw_size="${raw_size:-$suggested}"
    fi

    # --- Parse size ----------------------------------------------------------
    local size_mb
    if [[ "$raw_size" =~ ^([0-9]+)([MG]?)$ ]]; then
        size_mb="${BASH_REMATCH[1]}"
        case "${BASH_REMATCH[2]}" in
            G) size_mb=$((size_mb * 1024)) ;;
            M|"") ;;
        esac
    else
        err "Invalid size '${raw_size}'. Expected integer MB (e.g. 2048), or with suffix (e.g. 2G, 1024M)."
    fi

    # --- Validate ------------------------------------------------------------
    [[ "$size_mb" -ge 64 ]] || err "Size ${size_mb}M below 64M minimum."

    local avail_mb max_allowed
    avail_mb=$(df -B1M --output=avail / 2>/dev/null | tail -1 | tr -d ' ' || echo 0)
    [[ "$avail_mb" -gt 0 ]] || err "Could not determine free space on /."
    max_allowed=$(( avail_mb * 80 / 100 ))
    [[ "$size_mb" -le "$max_allowed" ]] \
        || err "Size ${size_mb}M exceeds 80% of free space on / (${max_allowed}M of ${avail_mb}M available)."

    # --- Allocate ------------------------------------------------------------
    info "Allocating ${size_mb}M at /swapfile..."
    if ! fallocate -l "${size_mb}M" /swapfile 2>/dev/null; then
        info "fallocate unavailable or failed — falling back to dd (slower)..."
        rm -f /swapfile
        dd if=/dev/zero of=/swapfile bs=1M count="${size_mb}" status=progress \
            || { rm -f /swapfile; err "dd failed to allocate swap file."; }
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null || { rm -f /swapfile; err "mkswap failed."; }
    swapon /swapfile           || { rm -f /swapfile; err "swapon failed."; }

    # --- fstab persistence ---------------------------------------------------
    if ! _swap_fstab_has /swapfile; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    # --- Swappiness ----------------------------------------------------------
    sysctl vm.swappiness=10 >/dev/null 2>&1 || true
    if ! grep -qE '^\s*vm\.swappiness\s*=' /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi

    local human
    human=$(du -h /swapfile 2>/dev/null | awk '{print $1}' || echo "${size_mb}M")
    log "Swap enabled: /swapfile (${human}), swappiness=10."
}
