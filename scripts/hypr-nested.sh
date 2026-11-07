# shellcheck shell=bash disable=SC2154,SC2034  # $scratch is the caller's; $nested_wl is for it
# Sourced, from the repo root: start a nested Hyprland (a window on the live desktop) on the
# repo's hyprland.lua with autostart off, and SIGKILL it whenever the sourcing script exits —
# a failed step must not leave it running.
#   nested_start [host]   sets $nested (its instance signature) and $nested_wl (its WAYLAND_DISPLAY)
#   n ARGS…               hyprctl into it
# Needs $scratch: the theme.lua / host.lua the config reads are written there.

nested_start() {
	local host="${1:-ivysaur}" before launch
	rm -rf "$scratch"
	mkdir -p "$scratch"
	cp "modules/desktop/hypr/hosts/$host.lua" "$scratch/host.lua"
	nix eval --raw --impure --expr \
		'(import ./modules/desktop/theme/render.nix { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }).hyprlandThemeLua' \
		>"$scratch/theme.lua"
	cp -r modules/desktop/hypr/scripts "$scratch/scripts"

	before="$(ls "$XDG_RUNTIME_DIR/hypr")"
	# start-hyprland (0.56+) is the launcher Hyprland asks for; bare `Hyprland` puts a warning on
	# its error overlay.
	launch=(Hyprland)
	command -v start-hyprland >/dev/null && launch=(start-hyprland --)
	# NO_SD_*: Hyprland 0.57 imports its display into the systemd user env at start and stops
	# graphical-session.target at exit, even nested — which takes the live session's shell,
	# portals and a11y bus down with it. setsid: the launcher and the compositor share one
	# process group, so the trap kills both.
	FICCIONES_HYPRDIR="$scratch" FICCIONES_HYPR_NO_AUTOSTART=1 HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_TARGET=1 \
		setsid "${launch[@]}" --config "$PWD/modules/desktop/hypr/hyprland.lua" >"$scratch/hyprland.log" 2>&1 &
	nested_pid=$!
	trap 'kill -9 -- -"$nested_pid" 2>/dev/null' EXIT

	nested=""
	for _ in $(seq 1 40); do
		sleep 0.5
		nested="$(comm -13 <(echo "$before") <(ls "$XDG_RUNTIME_DIR/hypr") | head -1 || true)"
		[ -n "$nested" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$nested/.socket.sock" ] && break
	done
	if [ -z "$nested" ]; then
		echo "nested Hyprland never came up; log: $scratch/hyprland.log" >&2
		return 1
	fi
	sleep 2
	nested_wl="$(n instances -j | jq -r --arg i "$nested" '.[] | select(.instance == $i) | .wl_socket')"
}

n() { HYPRLAND_INSTANCE_SIGNATURE="$nested" timeout 15 hyprctl "$@"; }
