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
GAP=12          # below the bar
STYLE="${QUAKE_STYLE:-slide}"  # slide | fade — the compositor never animates this window (no_anim), the
                               # script does: an opacity ramp, or a position ramp from above (eased,
                               # ~18 steps; each step is a hyprctl call, so it is not compositor-smooth)

# The compositor never animates this window (windowrule no_anim: a workspace move nudged it and
# every correction slid or unrolled). The fade is done here instead: a short opacity ramp,
# in place, through the window's own opacity props.
STEPS=8; STEP_S=0.018
prop() { hyprctl dispatch setprop "address:$addr" "$1" "$2" >/dev/null; }
fade() { # fade in|out — the window stays opaque while shown (a terminal over the sidecar)
  local i a
  for i in $(seq 1 $STEPS); do
    if [ "$1" = in ]; then a=$(( i * 100 / STEPS )); else a=$(( (STEPS - i) * 100 / STEPS )); fi
    if [ $a -ge 100 ]; then prop opacity 1; else prop opacity "0.$(printf '%02d' $a)"; fi
    sleep $STEP_S
  done
}
PREV="${XDG_RUNTIME_DIR:-/tmp}/quake-prev"
SLIDE_STEPS=18; SLIDE_S=0.011
slide() { # slide in|out between y0 (above the screen) and y1, ease-out
  local i t f yy
  for i in $(seq 1 $SLIDE_STEPS); do
    t=$(( i * 1000 / SLIDE_STEPS ))
    f=$(( 1000 - (1000 - t) * (1000 - t) / 1000 ))   # ease-out quad, per mille
    [ "$1" = out ] && f=$(( 1000 - f ))
    yy=$(( y0 + (y1 - y0) * f / 1000 ))
    hyprctl dispatch movewindowpixel "exact $x $yy,address:$addr" >/dev/null
    sleep $SLIDE_S
  done
}

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
  # shown → hide: fade out, unpin, park, then the opacity goes back to the rules
  if [ "$STYLE" = slide ]; then
    read -r x y1 wh < <(jq -r '"\(.at[0]) \(.at[1]) \(.size[1])"' <<<"$c"); y0=$(( y1 - wh - 60 )); slide out
  else fade out; fi
  [ "$pinned" = true ] && hyprctl dispatch pin "address:$addr" >/dev/null
  hyprctl dispatch movetoworkspacesilent "special:quake,address:$addr" >/dev/null
  prop opacity unset; prop opacity_override unset
  # focus goes back to the window that had it (Hyprland leaves it nowhere otherwise)
  prev=$(cat "$PREV" 2>/dev/null); [ -n "$prev" ] && hyprctl dispatch focuswindow "address:$prev" >/dev/null
  ring on
  exit 0
fi

# hidden → show on the focused monitor, pinned, on top, sized, focused.
# Below the bar (reserved top), centred on the whole monitor — over a sidecar, not beside it.
read -r mx my mw mh rt wsid < <(hyprctl -j monitors | jq -r '.[]|select(.focused)|"\(.x) \(.y) \(.width) \(.height) \(.reserved[1]) \(.activeWorkspace.id)"')
w=$(( mw * WIDTH_PCT / 100 ))
x=$(( mx + (mw - w) / 2 ))
y=$(( my + rt + GAP ))
hyprctl -j activewindow | jq -r .address > "$PREV"
ring off
# invisible first, sized and placed while still hidden; moving between workspaces nudges a
# floating window, so it is placed again after the move; then it fades in where it is
h=$(( mh * HEIGHT_PCT / 100 ))
y0=$(( y - h - 60 )); y1=$y
if [ "$STYLE" = slide ]; then start=$y0; prop opacity_override 1; prop opacity 1; else start=$y; prop opacity_override 1; prop opacity 0; fi
hyprctl --batch "dispatch setfloating address:$addr; dispatch resizewindowpixel exact $w $HEIGHT_PCT%,address:$addr; dispatch movewindowpixel exact $x $start,address:$addr" >/dev/null
hyprctl --batch "dispatch movetoworkspace $wsid,address:$addr; dispatch movewindowpixel exact $x $start,address:$addr" >/dev/null
[ "$pinned" = true ] || hyprctl dispatch pin "address:$addr" >/dev/null
hyprctl --batch "dispatch focuswindow address:$addr; dispatch alterzorder top,address:$addr" >/dev/null
if [ "$STYLE" = slide ]; then slide in; else fade in; fi
