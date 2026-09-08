#!/usr/bin/env bash
# Screenshot with flameshot (select, annotate, copy/save — Andrew, 2026-09-07). Its overlay
# comes up on the focused monitor; the flameshot-overlay rule in hyprland.lua floats and pins it.
#   shot-region.sh          select freely
#   shot-region.sh repeat   flameshot's last region pre-selected
# The capture comes out --raw and goes to wl-copy: flameshot (Qt6/Wayland) exits on copy and a
# Wayland selection dies with its owner, so the clipboard stayed empty (2026-09-08). wl-copy forks
# and holds it; cliphist's watcher stores it as usual.
set -euo pipefail
args=(gui --raw)
[[ "${1:-}" == "repeat" ]] && args+=(--last-region)
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT
flameshot "${args[@]}" > "$tmp" || true
[[ -s "$tmp" ]] && wl-copy --type image/png < "$tmp"   # Esc → empty file → clipboard untouched
