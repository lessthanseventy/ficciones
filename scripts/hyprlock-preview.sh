#!/usr/bin/env bash
# Photograph the generated hyprlock.conf in a NESTED Hyprland — the lock screen on a throwaway
# session, never yours. hyprlock has no dry-run, and its widget properties cannot be read off the
# binary (`size`, `position` and `rounding` are not even in its string table), so running it is
# the only way to know a config parses. Doing that on the live session means locking yourself out
# to find out; a nested instance costs nothing and can be photographed.
#
# The nested compositor runs on a private XDG_RUNTIME_DIR with no session bus: on the live one it
# imports its display into user systemd and starts the session target, and the live shell follows
# it there and dies with it. Its parent display is named by absolute path, which libwayland takes.
# One compositor per palette: a session unlocked once refuses the next lock ("seems we got yeeten").
#
# Usage: scripts/hyprlock-preview.sh [palette ...]   (default: every palette under theme/palettes)
# Writes $TMPDIR/hyprlock-preview/<palette>.png and prints the paths.
set -euo pipefail
cd "$(dirname "$0")/.."

for bin in Hyprland hyprlock hyprctl grim nix; do
	command -v "$bin" >/dev/null || {
		echo "missing: $bin"
		exit 1
	}
done
[ -n "${WAYLAND_DISPLAY:-}" ] || {
	echo "no WAYLAND_DISPLAY: run this from inside the session"
	exit 1
}

scratch="${TMPDIR:-/tmp}/hyprlock-preview"
rm -rf "$scratch"
mkdir -p "$scratch"
live="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
launch=(Hyprland)
command -v start-hyprland >/dev/null && launch=(start-hyprland --)

run=""
nested_pid=""
lock_pid=""
sig=""
display=""
nested() { env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="$run" HYPRLAND_INSTANCE_SIGNATURE="$sig" WAYLAND_DISPLAY="$display" "$@"; }

up() {
	# /tmp: a Wayland socket path has a length limit the scratch directories exceed
	run="$(mktemp -d /tmp/hlp.XXXXXX)"
	# defaults are all a preview needs; autostart off so it spawns no shell, no idle daemon
	printf -- '-- nested instance for a hyprlock preview\n' >"$run/nested.lua"
	env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="$run" WAYLAND_DISPLAY="$live" HYPRLAND_NO_SD_VARS=1 \
		FICCIONES_HYPR_NO_AUTOSTART=1 "${launch[@]}" --config "$run/nested.lua" >>"$scratch/nested.log" 2>&1 &
	nested_pid=$!
	display=""
	for _ in $(seq 1 60); do
		sleep 0.5
		for f in "$run"/wayland-*; do
			[ -S "$f" ] && display="$f"
		done
		[ -n "$display" ] && break
	done
	[ -n "$display" ] || {
		echo "nested Hyprland never came up; log: $scratch/nested.log"
		return 1
	}
	sig="$(ls "$run/hypr")"
}

down() {
	[ -n "$lock_pid" ] && kill "$lock_pid" 2>/dev/null || true
	lock_pid=""
	[ -n "$nested_pid" ] && {
		# asked to leave through its own socket; one of its forks outlives even that, and killed
		# before the wrapper is gone, the compositor comes back in safe mode under the watchdog
		[ -n "$sig" ] && nested hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || true
		for _ in $(seq 1 20); do
			kill -0 "$nested_pid" 2>/dev/null || break
			sleep 0.25
		done
		pkill -KILL -f -- "--config $run/nested.lua" 2>/dev/null || true
		wait "$nested_pid" 2>/dev/null || true
	}
	nested_pid=""
	sig=""
	[ -n "$run" ] && rm -rf "$run"
	run=""
}
trap down EXIT

palettes=("$@")
if [ ${#palettes[@]} -eq 0 ]; then
	for f in modules/desktop/theme/palettes/*.nix; do
		n="$(basename "$f" .nix)"
		[ "$n" = default ] || palettes+=("$n")
	done
fi

status=0
for name in "${palettes[@]}"; do
	conf="$scratch/$name.conf"
	shot="$scratch/$name.png"
	log="$scratch/$name.log"
	nix eval --impure --raw --expr "
    let lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib;
        palette = import ./modules/desktop/theme/palettes/$name.nix;
    in (import ./modules/desktop/theme/render.nix { inherit lib palette; }).hyprlockConf" >"$conf"
	up || {
		status=1
		down
		continue
	}
	# --grace keeps it up to be photographed; --no-fade-in so the shot is not a half-faded frame
	nested hyprlock --config "$conf" --grace 300 --no-fade-in >"$log" 2>&1 &
	lock_pid=$!
	# photographed once it holds the lock: a lock surface is no layer, so its log is the only word
	locked=""
	for _ in $(seq 1 40); do
		grep -q 'onLockLocked' "$log" && locked=1 && break
		sleep 0.25
	done
	[ -n "$locked" ] || {
		echo "  $name: hyprlock never took the lock"
		status=1
	}
	sleep 1
	nested grim "$shot" 2>/dev/null || {
		echo "  $name: grim failed"
		status=1
	}
	# hyprlang prints parse failures here; an unknown property is silent on screen but not in the log
	if grep -qiE "error|invalid|missing property|unknown" "$log"; then
		echo "  $name: CONFIG ERRORS"
		grep -iE "error|invalid|missing property|unknown" "$log" | head -5
		status=1
	else
		echo "  $name: ok -> $shot"
	fi
	down
done
exit $status
