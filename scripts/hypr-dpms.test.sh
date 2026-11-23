#!/usr/bin/env bash
# The screens-off bind must never be a trap: a key press or mouse move wakes them, and no
# move/focus-monitor chord is one key from it.
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

# modifier set of a bind line: the key expression with `.. M ..` as SUPER, minus its last key
mods() {
	grep -oE '^bind\("[^"]*"( \.\. M \.\. "[^"]*")*' |
		sed -E 's/^bind\(//; s/ \.\. M \.\. /SUPER/g; s/"//g' |
		sed -E 's/ *\+ *[^+]+$//' | tr -d ' ' | tr '+' '\n' | sort | tr '\n' '+'
}

dpms_line=$(grep -E '^bind\(.*dpms\(\{ action = "off"' "$lua" || true)
[ -n "$dpms_line" ] || {
	echo "hypr-dpms: no dpms-off bind found in $lua"
	exit 1
}
dmods=$(printf '%s\n' "$dpms_line" | mods)

while IFS= read -r line; do
	if [ "$(printf '%s\n' "$line" | mods)" = "$dmods" ]; then
		echo "hypr-dpms: a monitor chord shares the dpms bind's modifiers: $line"
		fail=1
	fi
done < <(grep -E '^bind\(.*(move_mon|monitor = )' "$lua" || true)

exit "$fail"
