#!/usr/bin/env bash
# Load modules/desktop/hypr/hyprland.lua in a NESTED Hyprland (a window on the live desktop),
# with autostart disabled, and diff its binds / options / rules against the live instance.
# Usage: scripts/hypr-lua-check.sh [host]   (default: ivysaur)
set -euo pipefail
cd "$(dirname "$0")/.."
host="${1:-ivysaur}"
scratch="${TMPDIR:-/tmp}/hypr-lua-check"
rm -rf "$scratch"; mkdir -p "$scratch"
cp "modules/desktop/hypr/hosts/$host.lua" "$scratch/host.lua"
nix eval --raw --impure --expr \
  '(import ./modules/desktop/theme/render.nix { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }).hyprlandThemeLua' \
  > "$scratch/theme.lua"
cp -r modules/desktop/hypr/scripts "$scratch/scripts"

live="$HYPRLAND_INSTANCE_SIGNATURE"
before="$(ls "$XDG_RUNTIME_DIR/hypr")"
FICCIONES_HYPRDIR="$scratch" FICCIONES_HYPR_NO_AUTOSTART=1 \
  Hyprland --config "$PWD/modules/desktop/hypr/hyprland.lua" >"$scratch/hyprland.log" 2>&1 &
pid=$!
nested=""
for _ in $(seq 1 40); do
  sleep 0.5
  nested="$(comm -13 <(echo "$before") <(ls "$XDG_RUNTIME_DIR/hypr") | head -1 || true)"
  [ -n "$nested" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$nested/.socket.sock" ] && break
done
if [ -z "$nested" ]; then echo "nested Hyprland never came up; log: $scratch/hyprland.log"; kill $pid || true; exit 1; fi
sleep 2
n() { HYPRLAND_INSTANCE_SIGNATURE="$nested" hyprctl "$@"; }
l() { HYPRLAND_INSTANCE_SIGNATURE="$live" hyprctl "$@"; }

echo "== configerrors (nested)"; n configerrors
# Lua binds report dispatcher "__lua" + a handle id, so the dispatcher/arg cannot be compared
# textually; keys, modmasks and flags can (dispatcher equivalence is the by-hand pass after the flip).
norm='.[] | {modmask, key, locked, mouse, release, repeat} | tostring'
echo "== binds diff (live vs nested) — key/mods/flags"
diff <(l binds -j | jq -r "$norm" | sort) <(n binds -j | jq -r "$norm" | sort) && echo "binds: identical ($(n binds -j | jq length) binds)"
echo "== binds: live dispatcher+arg per key (for the by-hand pass)"
l binds -j | jq -r '.[] | "\(.modmask)\t\(.key)\t\(.dispatcher) \(.arg)"' | sort > "$scratch/live-binds.tsv"; echo "  $scratch/live-binds.tsv"
echo "== options"
opts="general:gaps_in general:gaps_out general:border_size general:layout general:col.active_border general:col.inactive_border
decoration:rounding decoration:dim_inactive decoration:dim_strength decoration:shadow:range decoration:shadow:color decoration:blur:enabled
scrolling:column_width scrolling:explicit_column_widths scrolling:focus_fit_method scrolling:fullscreen_on_one_column scrolling:wrap_focus
misc:vrr misc:focus_on_activate misc:disable_hyprland_logo render:direct_scanout binds:allow_workspace_cycles
input:repeat_delay input:repeat_rate input:follow_mouse input:numlock_by_default input:touchpad:tap-to-click input:touchpad:clickfinger_behavior
animations:enabled group:groupbar:font_family misc:font_family"
for o in $opts; do
  # hyprlang reports bools as int and gradients as "custom type"; the Lua loader names the types.
  canon() { sed -E 's/^(int|bool): (1|true)$/true/; s/^(int|bool): (0|false)$/false/; s/^(custom type|gradient data|css gap data): //'; }
  a="$(l getoption "$o" 2>&1 | head -1 | canon)"; b="$(n getoption "$o" 2>&1 | head -1 | canon)"
  [ "$a" = "$b" ] && echo "  ok   $o = $a" || echo "  DIFF $o: live[$a] nested[$b]"
done
echo "== workspace rules"; diff <(l workspacerules | sort) <(n workspacerules | sort) && echo "workspacerules: identical"
echo "== animations"; diff <(l animations | sort) <(n animations | sort) && echo "animations: identical"
echo "== monitors (nested sees the nested window only; listed for the record)"; n monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)"'
kill $pid; wait $pid 2>/dev/null || true
echo "log: $scratch/hyprland.log"
