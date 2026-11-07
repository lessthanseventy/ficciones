#!/usr/bin/env bash
set -euo pipefail

# the flake's (modules/arch); ly's PATH has no nix profile on it
HYPRLAND=~/.nix-profile/bin/Hyprland

# Persistent log (survives reboot — /tmp is tmpfs)
LOG=~/hypr-startup.log
mkdir -p "$(dirname "$LOG")"

{
	echo
	echo "================================================================"
	echo "=== Hyprland launch attempt: $(date -Iseconds) ==="
	echo "=== Kernel: $(uname -r) ==="
	echo "=== Hyprland: $("$HYPRLAND" --version 2>&1 | head -1) ==="
	echo "================================================================"
} >>"$LOG"

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
	echo "=== SAFE MODE ENABLED (sentinel ~/.config/hypr/SAFE_MODE exists) ===" >>"$LOG"
fi

# Launch directly, not through start-hyprland: its watchdog restarts Hyprland in safe mode after
# every unclean exit, so one that dies at start keeps coming back; and off NixOS it decides on
# its own whether to wrap Hyprland in nixGL. A crash here lands back in ly; SAFE_MODE above is
# the manual way in. hyprland.lua turns off the warning this earns.
exec "$HYPRLAND" \
	--config /home/andrew/.config/hypr/hyprland.lua \
	"${EXTRA_ARGS[@]}" \
	>>"$LOG" 2>&1
