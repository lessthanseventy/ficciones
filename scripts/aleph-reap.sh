#!/usr/bin/env bash
# scripts/aleph-reap.sh — reap a stale `aleph:run` cockpit so a fresh launch can bind.
#
# aleph's in-process funes world listens on 4041 (distinct from the always-up
# funes.service on 4040 — two funes worlds, two DBs, one box). A cockpit that lost its
# TTY, or was backgrounded and forgotten, keeps holding 4041 and the next
# `mise run aleph:run` dies with `:eaddrinuse`. This guard runs before the launch and
# clears that stale listener.
#
# It kills ONLY the process LISTENING on the port (a beam.smp) — NOT tmux clients that
# merely hold an inherited fd (ss lists those too; killing them would murder the user's
# tmux). It also reaps any orphaned `mise run aleph:run` wrapper left hanging on a dead
# beam child (mise doesn't always exit when its beam is killed — seen 2026-08-16), while
# never touching the CURRENT invocation's own process tree.
#
# Safe to run any time; a free port is a no-op. Override the port with FUNES_MCP_PORT.
set -euo pipefail

PORT="${FUNES_MCP_PORT:-4041}"

# --- 1. reap the port listener -----------------------------------------------------------
# ss -tlnH "sport = :N" prints one line per listening socket with users:(("comm",pid=N,...)).
# Grab the listener pids (the first pid= in each line is the socket owner).
mapfile -t pids < <(ss -tlnH "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u || true)

if [ "${#pids[@]}" -gt 0 ]; then
  for pid in "${pids[@]}"; do
    cmd="$(ps -o comm= -p "$pid" 2>/dev/null || echo '?')"
    echo "aleph-reap: killing stale listener on $PORT — pid $pid ($cmd)"
    kill "$pid" 2>/dev/null || true
  done
  # Graceful first; SIGKILL any survivor after a beat.
  sleep 1
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "aleph-reap: pid $pid didn't exit — SIGKILL"
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
fi

# --- 2. reap orphaned mise/mix wrappers for THIS task -----------------------------------
# A `mise run aleph:run` whose beam child just died (step 1) can hang on the dead child.
# Kill any such wrapper that is NOT an ancestor of this shell — so the invoking mise is
# never touched. (Matches the stale-cockpit mise wrapper and any stray `mix aleph.run`.)
ancestors=" $$"
p="${PPID:-0}"
while [ "$p" -gt 1 ] 2>/dev/null; do
  ancestors="$ancestors $p"
  next="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
  [ -n "$next" ] || break
  p="$next"
done

orphans="$(pgrep -af 'mise run aleph:run|mix aleph\.run' 2>/dev/null || true)"
if [ -n "$orphans" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opid="${line%% *}"
    # Skip if it's this shell or an ancestor of it.
    case "$ancestors" in
      *" $opid "*) continue ;;
    esac
    echo "aleph-reap: killing orphaned wrapper — $line"
    kill "$opid" 2>/dev/null || true
  done <<<"$orphans"
  sleep 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opid="${line%% *}"
    case "$ancestors" in
      *" $opid "*) continue ;;
    esac
    kill -0 "$opid" 2>/dev/null && { echo "aleph-reap: pid $opid didn't exit — SIGKILL"; kill -9 "$opid" 2>/dev/null || true; }
  done <<<"$orphans"
fi

# --- 3. confirm --------------------------------------------------------------------------
if ss -tlnH "sport = :$PORT" 2>/dev/null | grep -q .; then
  echo "aleph-reap: WARNING — port $PORT still held after reap:" >&2
  ss -tlnp "sport = :$PORT" 2>/dev/null | sed 's/^/  /' >&2
  exit 1
fi
echo "aleph-reap: port $PORT free."