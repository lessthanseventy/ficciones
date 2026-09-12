#!/usr/bin/env bash
# Photograph the generated hyprlock.conf in a NESTED Hyprland — the lock screen on a throwaway
# session, never yours. hyprlock has no dry-run, and its widget properties cannot be read off the
# binary (`size`, `position` and `rounding` are not even in its string table), so running it is
# the only way to know a config parses. Doing that on the live session means locking yourself out
# to find out; a nested instance costs nothing and can be photographed.
# Its first run caught `$USER @ $HOST` — hyprlock has no $HOST and had been drawing the literal
# word on the lock screen (2026-09-12).
#
# Usage: scripts/hyprlock-preview.sh [palette ...]   (default: every palette under theme/palettes)
# Writes $TMPDIR/hyprlock-preview/<palette>.png and prints the paths.
set -euo pipefail
cd "$(dirname "$0")/.."

for bin in Hyprland hyprlock grim nix; do
  command -v "$bin" >/dev/null || { echo "missing: $bin"; exit 1; }
done
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "no WAYLAND_DISPLAY: run this from inside the session"; exit 1; }

scratch="${TMPDIR:-/tmp}/hyprlock-preview"
rm -rf "$scratch"; mkdir -p "$scratch"
# defaults are all a preview needs; autostart off so it spawns no shell, no idle daemon
printf -- '-- nested instance for a hyprlock preview\n' > "$scratch/nested.lua"

nested_pid=""; lock_pid=""
cleanup() {
  [ -n "$lock_pid" ] && kill "$lock_pid" 2>/dev/null || true
  [ -n "$nested_pid" ] && { kill "$nested_pid" 2>/dev/null || true; wait "$nested_pid" 2>/dev/null || true; }
}
trap cleanup EXIT

palettes=("$@")
if [ ${#palettes[@]} -eq 0 ]; then
  for f in modules/desktop/theme/palettes/*.nix; do palettes+=("$(basename "$f" .nix)"); done
fi

# one nested compositor for every palette; only hyprlock restarts between them
before="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | tr '\n' ' ')"
launch=(Hyprland); command -v start-hyprland >/dev/null && launch=(start-hyprland --)
FICCIONES_HYPR_NO_AUTOSTART=1 "${launch[@]}" --config "$scratch/nested.lua" >"$scratch/nested.log" 2>&1 &
nested_pid=$!
nested=""
for _ in $(seq 1 40); do
  sleep 0.5
  for f in "$XDG_RUNTIME_DIR"/wayland-*; do
    case " $before " in *" $f "*) ;; *) [ -S "$f" ] && nested="$(basename "$f")" ;; esac
  done
  [ -n "$nested" ] && break
done
[ -n "$nested" ] || { echo "nested Hyprland never came up; log: $scratch/nested.log"; exit 1; }
echo "nested display: $nested"
sleep 2

status=0
for name in "${palettes[@]}"; do
  conf="$scratch/$name.conf"; shot="$scratch/$name.png"; log="$scratch/$name.log"
  nix eval --impure --raw --expr "
    let lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib;
        palette = import ./modules/desktop/theme/palettes/$name.nix;
    in (import ./modules/desktop/theme/render.nix { inherit lib palette; }).hyprlockConf" > "$conf"
  # --grace keeps it up to be photographed; --no-fade-in so the shot is not a half-faded frame
  WAYLAND_DISPLAY="$nested" hyprlock --config "$conf" --grace 300 --no-fade-in >"$log" 2>&1 &
  lock_pid=$!
  sleep 4
  WAYLAND_DISPLAY="$nested" grim "$shot" 2>/dev/null || { echo "  $name: grim failed"; status=1; }
  # hyprlang prints parse failures here; an unknown property is silent on screen but not in the log
  if grep -qiE "error|invalid|missing property|unknown" "$log"; then
    echo "  $name: CONFIG ERRORS"; grep -iE "error|invalid|missing property|unknown" "$log" | head -5; status=1
  else
    echo "  $name: ok -> $shot"
  fi
  kill "$lock_pid" 2>/dev/null || true; wait "$lock_pid" 2>/dev/null || true; lock_pid=""
done
exit $status
