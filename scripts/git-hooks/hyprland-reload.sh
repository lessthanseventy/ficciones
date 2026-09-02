#!/usr/bin/env bash
# Reload the live Hyprland after any operation that rewrites the working tree.
#
# ~/.config/hypr/hyprland.conf is an out-of-store symlink into THIS repo, so the running
# compositor reads a file git owns. Two consequences, both silent:
#
#   1. A checkout onto a commit without modules/desktop/ (main before this landed, and every
#      older branch) deletes the file. The symlink dangles, and Hyprland's next reload — its
#      own watch firing, or caelestia applying a scheme — finds no config, loads built-in
#      defaults, and reports NO error. Measured live: 144 binds and the scrolling layout down
#      to 8 binds and dwindle, and it stays there, because nothing reloads once the file
#      comes back.
#   2. A checkout that REPLACES the file leaves the compositor running the old branch's
#      config until something happens to reload it.
#
# Reload is idempotent and does not re-run exec-once, so reloading unconditionally is cheaper
# than working out whether modules/desktop/ was part of the diff.
#
# Never fail the git operation — a hook that breaks checkout is worse than a stale desktop.
set -u

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
conf="$root/modules/desktop/hypr/hyprland.conf"

hyprctl="$(command -v hyprctl 2>/dev/null || true)"
[ -n "$hyprctl" ] || exit 0

shopt -s nullglob
instances=("${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/)
[ ${#instances[@]} -gt 0 ] || exit 0

# Reloading with the file gone is the one thing that must NOT happen: it is precisely what
# resets the compositor to defaults. Warn instead, and leave the running config alone.
if [ ! -e "$conf" ]; then
  echo "hyprland-reload: modules/desktop is not on this commit; ~/.config/hypr/hyprland.conf now dangles." >&2
  echo "hyprland-reload: the live desktop is untouched, but any reload from here lands on Hyprland defaults." >&2
  echo "hyprland-reload: return to a commit that carries it, then run 'hyprctl reload'." >&2
  exit 0
fi

for inst in "${instances[@]}"; do
  HYPRLAND_INSTANCE_SIGNATURE="$(basename "$inst")" "$hyprctl" reload >/dev/null 2>&1 || true
done

exit 0
