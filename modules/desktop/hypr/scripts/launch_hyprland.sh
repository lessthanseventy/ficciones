#!/usr/bin/env bash
set -euo pipefail

# Persistent log (survives reboot — /tmp is tmpfs)
LOG=~/hypr-startup.log
mkdir -p "$(dirname "$LOG")"

{
    echo
    echo "================================================================"
    echo "=== Hyprland launch attempt: $(date -Iseconds) ==="
    echo "=== Kernel: $(uname -r) ==="
    echo "=== Hyprland: $(/usr/bin/Hyprland --version 2>&1 | head -1) ==="
    echo "================================================================"
} >> "$LOG"

# Clear display variables
unset DISPLAY
unset WAYLAND_DISPLAY

# Wayland environment
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

# Safe-mode toggle: `touch ~/.config/hypr/SAFE_MODE` before launching
# to start Hyprland with a minimal built-in config (bypasses hyprland.lua)
EXTRA_ARGS=()
if [[ -f ~/.config/hypr/SAFE_MODE ]]; then
    EXTRA_ARGS+=(--safe-mode)
    echo "=== SAFE MODE ENABLED (sentinel ~/.config/hypr/SAFE_MODE exists) ===" >> "$LOG"
fi

# Launch directly — NOT start-hyprland (that's a restart-loop watchdog that
# fork-bombs the system + locks the GPU if Hyprland fails immediately).
exec /usr/bin/Hyprland \
    --config /home/andrew/.config/hypr/hyprland.lua \
    "${EXTRA_ARGS[@]}" \
    >> "$LOG" 2>&1
