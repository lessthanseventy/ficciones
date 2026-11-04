#!/usr/bin/env bash
# The private desktop must start its own accessibility bus and leave the live one alone. Detection
# only: if isolation regressed, the damage is done by the time this goes red, so it stays out of
# `mise run check` and runs on demand, after a change to headless-desktop.sh.
set -uo pipefail

live="/run/user/$(id -u)"
state() {
	stat -c '%i %Y' "$live/at-spi/bus_0"
	systemctl --user show xdg-document-portal.service -p MainPID
	mountpoint "$live/doc"
}
left() { ls -d /tmp/hd.* 2>/dev/null | wc -l; }
left_before="$(left)"
before="$(state)" || {
	echo "the live desktop is not healthy, nothing to compare:" >&2
	echo "$before" >&2
	exit 1
}

scripts/headless-desktop.sh bash -c '
  case "$XDG_RUNTIME_DIR" in /tmp/hd.*) ;; *) echo "runtime dir not private: $XDG_RUNTIME_DIR"; exit 1 ;; esac
  agent-desktop list-windows >/dev/null
  # bus_<display> under X, bus without one
  compgen -G "$XDG_RUNTIME_DIR/at-spi/bus*" >/dev/null || { echo "the private accessibility bus never started"; exit 1; }
'
rc=$?
[ "$rc" = 0 ] || {
	echo "FAIL: the private desktop (exit $rc)" >&2
	exit 1
}

after="$(state)" || true
[ "$before" = "$after" ] || {
	printf 'FAIL: the live desktop changed\nbefore:\n%s\nafter:\n%s\n' "$before" "$after" >&2
	exit 1
}
sleep 1
[ "$(left)" = "$left_before" ] || {
	echo "FAIL: a private runtime dir survived: $(ls -d /tmp/hd.*)" >&2
	exit 1
}
echo "ok: private bus up, live accessibility socket and document portal unchanged"
