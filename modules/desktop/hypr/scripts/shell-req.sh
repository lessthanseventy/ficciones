#!/usr/bin/env bash
# A request to the running astal shell over D-Bus directly (~15 ms) — the `astal-shell` wrapper
# starts gjs to do the same and takes ~350 ms, too slow for focus and resize keys.
args=$(printf "'%s'," "$@"); args="[${args%,}]"
exec gdbus call --session --dest io.Astal.astal-shell --object-path /io/Astal/Application \
  --method io.Astal.Application.Request "$args" >/dev/null
