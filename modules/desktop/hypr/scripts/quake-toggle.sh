#!/usr/bin/env bash
# Quake-style dropdown terminal for Hyprland, bound to F12 globally (see hyprland.lua).
# A ghostty window (class com.ghostty.quake) parks on the special:quake workspace while hidden.
# Shown, it is moved to the focused monitor's active workspace and PINNED: Hyprland renders
# pinned windows above everything else, and the shell's sidecar is a pinned window, so an
# unpinned quake sat behind it (2026-09-06). Sized as a centred band at the top of the focused
# monitor (percent size + logical monitor origin are both scale-safe).
# NB: the class must be a valid GTK app-id (reverse-DNS, needs a dot) or ghostty
# silently ignores --class and falls back to com.mitchellh.ghostty.
CLASS="com.ghostty.quake"
WIDTH_PCT=70    # of the monitor, centred
HEIGHT_PCT=55

client() { hyprctl -j clients | jq -c --arg c "$CLASS" '.[]|select(.class==$c)' | head -1; }

# Spawn on first use, then wait for it to map.
if [ -z "$(client)" ]; then
  hyprctl dispatch exec "[workspace special:quake silent] ghostty --class=$CLASS"
  for _ in $(seq 1 30); do [ -n "$(client)" ] && break; sleep 0.1; done
fi

c=$(client)
addr=$(jq -r .address <<<"$c")
ws=$(jq -r .workspace.name <<<"$c")
pinned=$(jq -r .pinned <<<"$c")
[ -n "$addr" ] || exit 1

# The shell's sidecar ring is a layer surface above every window; the shell drops it while the
# quake is up (asked here, so it is gone before the slide rather than half a second in).
ring() { "$(dirname "$0")/shell-req.sh" sidecar ring "$1" 2>/dev/null || true; }

if [ "$ws" != "special:quake" ]; then
  # shown → hide: slide up off the top (a move animates), then unpin and park
  read -r wx wy wh < <(jq -r '"\(.at[0]) \(.at[1]) \(.size[1])"' <<<"$c")
  hyprctl dispatch movewindowpixel "exact $wx $(( wy - wh - 40 )),address:$addr" >/dev/null
  sleep 0.25
  [ "$pinned" = true ] && hyprctl dispatch pin "address:$addr" >/dev/null
  hyprctl dispatch movetoworkspacesilent "special:quake,address:$addr" >/dev/null
  ring on
  exit 0
fi

# hidden → show on the focused monitor, pinned, on top, sized, focused.
# Below the bar (reserved top), centred on the whole monitor — over a sidecar, not beside it.
read -r mx my mw mh rt wsid < <(hyprctl -j monitors | jq -r '.[]|select(.focused)|"\(.x) \(.y) \(.width) \(.height) \(.reserved[1]) \(.activeWorkspace.id)"')
w=$(( mw * WIDTH_PCT / 100 ))
x=$(( mx + (mw - w) / 2 ))
y=$(( my + rt ))
h=$(( mh * HEIGHT_PCT / 100 ))
ring off
# a moved window animates from where it was: park it above the screen first, while still
# hidden, so the move slides it down from the top
hyprctl --batch "dispatch setfloating address:$addr; dispatch resizewindowpixel exact $w $HEIGHT_PCT%,address:$addr; dispatch movewindowpixel exact $x $(( y - h - 40 )),address:$addr" >/dev/null
hyprctl --batch "dispatch movetoworkspace $wsid,address:$addr; dispatch movewindowpixel exact $x $y,address:$addr" >/dev/null
[ "$pinned" = true ] || hyprctl dispatch pin "address:$addr" >/dev/null
hyprctl --batch "dispatch focuswindow address:$addr; dispatch alterzorder top,address:$addr" >/dev/null
