#!/usr/bin/env bash
# Region screenshot that remembers its region.
#   shot-region.sh          select a region, capture it, remember it
#   shot-region.sh repeat   capture the remembered region again, no selection
set -euo pipefail

state="${XDG_RUNTIME_DIR:-/tmp}/hypr-last-region"

if [[ "${1:-}" == "repeat" ]]; then
    if [[ ! -s "$state" ]]; then
        notify-send -u critical "Screenshot" "No remembered region yet — grab one with Super+Shift+S first."
        exit 1
    fi
    geom=$(<"$state")
else
    # slurp exits non-zero when the selection is cancelled; don't clobber the saved region.
    geom=$(slurp) || exit 0
    printf '%s' "$geom" > "$state"
fi

grim -g "$geom" - | swappy -f -
