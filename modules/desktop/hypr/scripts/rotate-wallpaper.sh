#!/usr/bin/env bash
# Rotate wallpapers on every monitor every $INTERVAL seconds, through hyprpaper alone.
# Replaces ~/.local/bin/rotate-wallpaper (Arch-era): that one asked caelestia for the laptop
# wallpaper, and caelestia's scheme applier rewrote gtk.css, cava and btop behind the palette
# generators every five minutes. Colours are palette.nix's business, not the wallpaper's.
set -uo pipefail

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
INTERVAL="${INTERVAL:-300}"

pick() {
    find "$WALLPAPER_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -print0 | shuf -z -n 1 | tr '\0' '\n'
}

wait_for_hyprpaper() {
    if ! pgrep -x hyprpaper >/dev/null; then
        nohup hyprpaper >/dev/null 2>&1 &
    fi
    local sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr"
    for _ in $(seq 1 20); do
        if compgen -G "$sock"/*/.hyprpaper.sock >/dev/null; then return 0; fi
        sleep 0.3
    done
    return 1
}

rotate() {
    wait_for_hyprpaper || { echo "$(date): hyprpaper never came up"; return 1; }
    local mon file
    while IFS= read -r mon; do
        IFS= read -r file < <(pick)
        [ -n "$file" ] || { echo "$(date): no wallpapers in $WALLPAPER_DIR"; return 1; }
        hyprctl hyprpaper preload "$file" >/dev/null 2>&1
        hyprctl hyprpaper wallpaper "$mon,$file" >/dev/null 2>&1
        echo "$(date): $mon -> $(basename "$file")"
    done < <(hyprctl monitors -j | jq -r '.[].name')
    hyprctl hyprpaper unload unused >/dev/null 2>&1
}

rotate
while true; do
    sleep "$INTERVAL"
    rotate
done
