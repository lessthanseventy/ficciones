#!/usr/bin/env bash
# gpu-hang-watch.sh, on kernel lines captured from real i915 hangs: the shell is restarted once
# per burst, another program gets one notice and is never killed, and other lines do nothing.
watch="$(cd "$(dirname "$0")" && pwd)/gpu-hang-watch.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/proc/3343354" "$t/proc/1945244"
echo '0::/user.slice/user-1000.slice/user@1000.service/app.slice/astal-shell.service' >"$t/proc/3343354/cgroup"
echo '0::/user.slice/user-1000.slice/session-c1.scope' >"$t/proc/1945244/cgroup"
for c in systemctl notify-send; do
	printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$c" "$t" >"$t/bin/$c"
	chmod +x "$t/bin/$c"
done

lines='Fence expiration time out i915-0000:00:02.0:weston[2257054]:6a!
Fence expiration time out i915-0000:00:02.0:ghostty[1945244]:3c9da!
Fence expiration time out i915-0000:00:02.0:ghostty[1945244]:3c9d8!
Fence expiration time out i915-0000:00:02.0:gjs[3343354]:e24!
Fence expiration time out i915-0000:00:02.0:gjs[3343354]:212!
i915 0000:00:02.0: [drm] GPU HANG: ecode 12:1:85dffffb, in gjs [3343354]
i915 0000:00:02.0: [drm] gjs[3343354] context reset due to GPU hang
usb 1-1: new high-speed USB device number 7 using xhci_hcd'

run() {
	rm -f "$t/calls" "$t/hang.log"
	printf '%s\n' "$lines" | PATH="$t/bin:$PATH" GPU_HANG_PROC="$t/proc" GPU_HANG_WINDOW="$1" bash "$watch" "$t/hang.log"
}

bad=0
want() {
	[ "$(cat "$t/calls")" = "$2" ] || {
		echo "gpu-hang-watch: $1: expected"
		echo "$2"
		echo "got"
		cat "$t/calls"
		bad=1
	}
}

run 30
want "a burst is one action per program" 'notify-send -u critical ghostty lost its GPU context: restart it pid 1945244
systemctl --user restart astal-shell'
[ "$(wc -l <"$t/hang.log")" = 2 ] || {
	echo "gpu-hang-watch: the log has $(wc -l <"$t/hang.log") lines for 2 events"
	bad=1
}

run 0
want "past the window each line acts again" 'notify-send -u critical ghostty lost its GPU context: restart it pid 1945244
notify-send -u critical ghostty lost its GPU context: restart it pid 1945244
systemctl --user restart astal-shell
systemctl --user restart astal-shell
systemctl --user restart astal-shell'

exit "$bad"
