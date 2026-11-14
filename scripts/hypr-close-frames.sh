#!/usr/bin/env bash
# Photograph a window closing in a nested Hyprland, with HyprWindowShade loaded as at login:
# open a kitty, close it, and grab frames of the nested output while the close shader plays.
# Prints the contact sheet's path. Usage: scripts/hypr-close-frames.sh [frames] (default: 12)
set -euo pipefail
cd "$(dirname "$0")/.."
frames="${1:-12}"
scratch="${TMPDIR:-/tmp}/hypr-close-frames"
# shellcheck source=/dev/null  # linted on its own
. scripts/hypr-nested.sh
nested_start
: "${nested_wl:?}"

loaded=""
so=~/.local/share/hypr/plugins/hyprwindowshade.so
[ -f "$so" ] && loaded="$(n plugin load "$so")"
[ "$loaded" = "ok" ] || {
	echo "HyprWindowShade did not load: ${loaded:-no .so installed}"
	exit 1
}

WAYLAND_DISPLAY="$nested_wl" kitty --class close-frames -o font_size=28 \
	sh -c 'printf "\n   closing\n\n"; seq 1 40; sleep 60' >/dev/null 2>&1 &
addr=""
for _ in $(seq 1 30); do
	sleep 0.5
	addr="$(n clients -j | jq -r '.[] | select(.class == "close-frames") | .address')"
	[ -n "$addr" ] && break
done
[ -n "$addr" ] || {
	echo "kitty never mapped in the nested instance"
	exit 1
}
echo "tags: $(n clients -j | jq -c '.[] | select(.class == "close-frames") | .tags')"
sleep 1

shots="$scratch/frames"
mkdir -p "$shots"
WAYLAND_DISPLAY="$nested_wl" grim "$shots/00.png"
n dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null
t0="$(date +%s%N)"
for i in $(seq -w 1 "$frames"); do
	WAYLAND_DISPLAY="$nested_wl" grim -l 0 "$shots/$i.png"
done
ms=$((($(date +%s%N) - t0) / 1000000))
magick montage "$shots"/*.png -tile 4x -geometry 320x200+2+2 -background '#333' "$scratch/close-sheet.png"
echo "sheet: $scratch/close-sheet.png (first frame before the close, then $frames over ${ms} ms)"
