#!/usr/bin/env bash
# Screens-off must never be a trap: no bind turns them off, and a key press or mouse move wakes
# them when hypridle has.
set -euo pipefail
cd "$(dirname "$0")/.."
lua=modules/desktop/hypr/hyprland.lua
fail=0

for opt in key_press_enables_dpms mouse_move_enables_dpms; do
	grep -Eq "^\s*$opt = true," "$lua" || {
		echo "hypr-dpms: misc.$opt is not true in $lua"
		fail=1
	}
done

if grep -En '^\s*bind\(.*dpms' "$lua"; then
	echo "hypr-dpms: a bind dispatches dpms in $lua"
	fail=1
fi

exit "$fail"
