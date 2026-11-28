#!/usr/bin/env bash
# Reads kernel log lines on stdin. For each program i915 names in a GPU hang or a fence timeout:
# the shell is restarted, any other gets a desktop notice (a terminal may hold work, so nothing
# is killed). One action per program per window, as a hang logs a burst of lines.
set -u
log=${1:?usage: gpu-hang-watch.sh <log file>}
proc=${GPU_HANG_PROC:-/proc}
window=${GPU_HANG_WINDOW:-30}
declare -A last

while IFS= read -r line; do
	if [[ $line =~ GPU\ HANG:.*,\ in\ ([^ ]+)\ \[([0-9]+)\] ]] ||
		[[ $line =~ Fence\ expiration\ time\ out\ .*:([^:[]+)\[([0-9]+)\]: ]]; then
		comm=${BASH_REMATCH[1]} pid=${BASH_REMATCH[2]}
	else
		continue
	fi

	# gone already: its stale frames went with it
	[ -e "$proc/$pid" ] || continue
	if grep -q '/astal-shell\.service$' "$proc/$pid/cgroup" 2>/dev/null; then
		key=shell
	else
		key=$pid
	fi
	[ -n "${last[$key]:-}" ] && [ $((SECONDS - last[$key])) -lt "$window" ] && continue
	last[$key]=$SECONDS

	if [ "$key" = shell ]; then
		did="restarted astal-shell"
		systemctl --user restart astal-shell || did="could not restart astal-shell"
	else
		did="notice"
		notify-send -u critical "$comm lost its GPU context: restart it" "pid $pid" || did="could not send a notice"
	fi
	printf '%s %s[%s] %s: %s\n' "$(date -Is)" "$comm" "$pid" "$did" "$line" >>"$log"

	# root only on a stock kernel; kept when it can be read, as the next hang overwrites it
	for err in /sys/class/drm/card*/error; do
		[ -r "$err" ] && cp "$err" "${log%.log}-$(date +%Y%m%dT%H%M%S)-$(basename "$(dirname "$err")").error" 2>/dev/null
	done
done
