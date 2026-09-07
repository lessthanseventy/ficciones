#!/usr/bin/env bash
# Screenshot with flameshot (select, annotate, copy/save — Andrew, 2026-09-07). Its overlay
# comes up on the focused monitor; the flameshot-overlay rule in hyprland.lua floats and pins it.
#   shot-region.sh          select freely
#   shot-region.sh repeat   flameshot's last region pre-selected
set -euo pipefail
args=(gui)
[[ "${1:-}" == "repeat" ]] && args+=(--last-region)
exec flameshot "${args[@]}"
