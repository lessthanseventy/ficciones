#!/usr/bin/env bash
# Quake-style dropdown terminal for Hyprland, bound to F12 globally (see hyprland.conf).
# A ghostty window (class com.ghostty.quake) lives on the special:quake workspace, so
# the toggle works no matter which window is focused. It is sized/positioned as a
# full-width top band on whichever monitor is currently focused (dual-monitor safe).
# NB: the class must be a valid GTK app-id (reverse-DNS, needs a dot) or ghostty
# silently ignores --class and falls back to com.mitchellh.ghostty.
CLASS="com.ghostty.quake"
HEIGHT_PCT="45%"

exists() { hyprctl -j clients | jq -e --arg c "$CLASS" '.[]|select(.class==$c)' >/dev/null 2>&1; }

# Spawn on first use, then wait for it to map.
if ! exists; then
  hyprctl dispatch exec "[workspace special:quake silent] ghostty --class=$CLASS"
  for _ in $(seq 1 30); do exists && break; sleep 0.1; done
fi

hyprctl dispatch togglespecialworkspace quake

# Re-anchor to the focused monitor as a full-width top band (percent size + logical
# monitor origin are both scale-safe).
addr=$(hyprctl -j clients | jq -r --arg c "$CLASS" '.[]|select(.class==$c)|.address' | head -1)
read -r mx my < <(hyprctl -j monitors | jq -r '.[]|select(.focused)|"\(.x) \(.y)"')
if [ -n "$addr" ] && [ -n "$mx" ]; then
  hyprctl dispatch resizewindowpixel "exact 100% $HEIGHT_PCT,address:$addr"
  hyprctl dispatch movewindowpixel "exact $mx $my,address:$addr"
fi
