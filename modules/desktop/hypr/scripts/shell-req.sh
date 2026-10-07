#!/usr/bin/env bash
# A request to the running astal shell over D-Bus directly (~15 ms) — the `astal-shell` wrapper
# starts gjs to do the same and takes ~350 ms, too slow for focus and resize keys.
# --timeout: a shell mid-restart still owns the name but never answers, and gdbus's default
# 25 s wait held a key's script that long. busctl,
# not gdbus: the signature is given, so the timeout bounds the whole call (gdbus took ~3 s more).
exec busctl --user call --timeout=1 io.Astal.astal-shell /io/Astal/Application io.Astal.Application \
  Request as "$#" "$@" >/dev/null
