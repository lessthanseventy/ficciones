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
# Hyprland on a .lua config takes lua on the socket (2026-09-07): every dispatch is an hl.dsp
# expression; the window is always this one
d() { hyprctl dispatch "$1" >/dev/null; }
W() { printf 'window = "address:%s"' "$addr"; }
prop() { d "hl.dsp.window.set_prop({ prop = \"$1\", value = \"$2\", $(W) })"; }
place() { d "hl.dsp.window.move({ x = $1, y = $2, relative = false, $(W) })"; }
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
    place "$x" "$yy"
    sleep $SLIDE_S
  done
}

# jq is the flake's (modules/desktop home.packages); without it the lookup below is empty and
# every press spawns another terminal onto the hidden workspace (16 of them, 2026-09-08)
command -v jq >/dev/null || { notify-send -u critical "quake" "jq missing — not spawning"; exit 1; }
# one toggle at a time: the slide is 18 hyprctl calls, seconds under load (a build in the
# terminal itself, 2026-09-08), and a second press mid-slide ran a second copy against the
# same window — shown and not hideable until the two settled
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/quake-toggle.lock"; flock -n 9 || exit 0
client() { hyprctl -j clients | jq -c --arg c "$CLASS" '.[]|select(.class==$c)' | head -1; }

# Spawn on first use, then wait for it to map.
if [ -z "$(client)" ]; then
  d "hl.dsp.exec_cmd(\"[workspace special:quake silent] ghostty --class=$CLASS\")"
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
  [ "$pinned" = true ] && d "hl.dsp.window.pin({ $(W) })"
  d "hl.dsp.window.move({ workspace = \"special:quake\", follow = false, $(W) })"
  # opacity takes a number on the lua socket ("unset" fails to parse); 1 is the default rule's
  prop opacity 1; prop opacity_override unset
  # focus goes back to the window that had it (Hyprland leaves it nowhere otherwise)
  prev=$(cat "$PREV" 2>/dev/null); [ -n "$prev" ] && d "hl.dsp.focus({ window = \"address:$prev\" })"
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
# transparent across the workspace move for both styles: Hyprland clamps a floating window
# onto the monitor when it changes workspace, so the one parked above the screen showed for a
# frame before the place below put it back (Andrew, 2026-09-08: "glitches visible then slides")
if [ "$STYLE" = slide ]; then start=$y0; else start=$y; fi
prop opacity_override 1; prop opacity 0
d "hl.dsp.window.float({ action = \"on\", $(W) })"
d "hl.dsp.window.resize({ x = $w, y = $h, relative = false, $(W) })"
place "$x" "$start"
d "hl.dsp.window.move({ workspace = \"$wsid\", follow = true, $(W) })"
place "$x" "$start"
[ "$pinned" = true ] || d "hl.dsp.window.pin({ $(W) })"
d "hl.dsp.focus({ $(W) })"
d "hl.dsp.window.alter_zorder({ mode = \"top\", $(W) })"
if [ "$STYLE" = slide ]; then prop opacity 1; slide in; else fade in; fi
# focus again once it has landed — asked while it hung above the screen, focus did not stick
d "hl.dsp.focus({ $(W) })"
