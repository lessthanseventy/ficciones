#!/usr/bin/env bash
# Run a command against a private headless desktop: its own compositor, session bus and accessibility
# bus, so an agent can launch an app and act on it without touching the live one.
#
# The environment has to be isolated BEFORE dbus-run-session: what the bus activates inherits the
# daemon's, and an at-spi-bus-launcher left on the real XDG_RUNTIME_DIR deletes the live
# at-spi/bus_0 when it exits.
set -euo pipefail

if [ "${1:-}" != "--inner" ]; then
	[ $# -gt 0 ] || {
		echo "usage: $0 <command> [args...]" >&2
		exit 2
	}
	# /tmp, because a Wayland socket path has a length limit the scratch directories exceed
	run="$(mktemp -d /tmp/hd.XXXXXX)"
	# What the bus activates outlives the session: dconf-service recreates $run after the rm and keeps
	# any inherited output pipe open, and the document portal and gvfs leave FUSE mounts. Each holds
	# session.log, which nothing outside this session can.
	trap 'fuser -sk "$run/session.log" 2>/dev/null || true
    for m in "$run"/doc "$run"/gvfs; do fusermount3 -uz "$m" 2>/dev/null || true; done; rm -rf "$run"' EXIT
	nix shell nixpkgs#weston nixpkgs#dbus nixpkgs#at-spi2-core -c bash "$0" --inner "$run" "$@"
	exit $?
fi

run="$2"
shift 2
mkdir -p "$run/home"
export XDG_RUNTIME_DIR="$run" HOME="$run/home" XDG_CONFIG_HOME="$run/home/.config" \
	XDG_CACHE_HOME="$run/home/.cache" XDG_DATA_HOME="$run/home/.local/share" \
	WAYLAND_DISPLAY=wl GDK_BACKEND=wayland GTK_USE_PORTAL=0
unset DISPLAY AT_SPI_BUS_ADDRESS DBUS_SESSION_BUS_ADDRESS

conf="$(dirname "$(dirname "$(readlink -f "$(command -v dbus-daemon)")")")/share/dbus-1/session.conf"
exec 3>&1 4>&2 >"$run/session.log" 2>&1
exec dbus-run-session --config-file="$conf" -- bash -c '
  weston --backend=headless --socket=wl --idle-time=0 3>&- 4>&- &
  weston=$!
  sleep 2
  rc=0
  "$@" >&3 2>&4 3>&- 4>&- || rc=$?
  kill "$weston" 2>/dev/null || true
  wait "$weston" 2>/dev/null
  exit "$rc"
' _ "$@"
