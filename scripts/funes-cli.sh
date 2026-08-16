#!/usr/bin/env bash
# funes CLI — the mise parity pack (capability-map move #2): operate/script the LIVE
# channel from the shell, the human+Claude-Code peer to the agents' MCP tools.
#
# Every subcommand runs through `bin/funes rpc` INTO the running service node — a token
# minted anywhere else dies with its node and 401s, and roster/presence is in-memory
# there, so a fresh `eval` node would see neither. The service must be up (the
# `systemd --user` unit, or a dev daemon). Thin and deliberate: operate access, NOT a
# second cockpit — aleph is the human's rich surface.
#
# Usage: mise run funes:{spawn|roster|dossier|post} -- [args]
set -euo pipefail

FUNES="$(dirname "$0")/../modules/funes/_build/prod/rel/funes/bin/funes"
[ -x "$FUNES" ] || { echo "no release at $FUNES — run 'mise run funes:release' first" >&2; exit 1; }

# Escape a string for embedding as an Elixir "..." literal: backslash first, then quote.
# rpc evaluates IN the service node, so the caller's env can't carry args — they cross
# as code.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
int() { case "$1" in ('' | *[!0-9]*) return 1 ;; (*) return 0 ;; esac; }

cmd="${1:-}"
shift || true

case "$cmd" in
  spawn)
    title="${1:-}"; agent="${2:-}"
    { [ -n "$title" ] && [ -n "$agent" ]; } ||
      { echo 'usage: mise run funes:spawn -- "<thread title>" <agent-name>' >&2; exit 2; }
    # Open a thread, staff the agent (register if new), mint the token, print the
    # export FUNES_* block to paste into a fresh pi pane. `; :ok` keeps rpc's echoed
    # return off the clean block.
    exec "$FUNES" rpc "Funes.MCP.Spawn.env(\"$(esc "$title")\", \"$(esc "$agent")\"); :ok"
    ;;

  roster)
    # Who's on the clock (Staff.roster): every live session, warm ● / cold ○.
    exec "$FUNES" rpc '
      Funes.Staff.roster()
      |> Enum.map_join("\n", fn r ->
        mark = if r.warm?, do: "●", else: "○"
        pane = if r.pane_ref, do: " [" <> r.pane_ref <> "]", else: ""
        "#{mark} #{r.agent} — ##{r.thread_id} #{r.thread_title}#{pane}"
      end)
      |> then(fn "" -> "(no one on the clock)"; s -> s end)
      |> IO.puts()'
    ;;

  dossier)
    tid="${1:-}"
    int "$tid" || { echo 'usage: mise run funes:dossier -- <thread-id>' >&2; exit 2; }
    # The thread's brief — the same Board.in_scope |> Brief.scope the get_dossier MCP
    # tool renders, pretty-printed for the shell.
    exec "$FUNES" rpc "%Funes.Thread{id: $tid} |> Funes.Board.in_scope() |> Funes.MCP.Brief.scope() |> inspect(pretty: true, limit: :infinity) |> IO.puts()"
    ;;

  post)
    tid="${1:-}"; shift || true
    body="$*"
    { int "$tid" && [ -n "$body" ]; } ||
      { echo 'usage: mise run funes:post -- <thread-id> <message text…>' >&2; exit 2; }
    # Post as the operator (FUNES_OPERATOR, default andrew) — the human participating
    # on a thread from the CLI, parity with the agents' post_message.
    exec "$FUNES" rpc "op = Application.get_env(:funes, :operator, \"andrew\"); {:ok, m} = Funes.Channel.post(%{thread_id: $tid, author: op, body: \"$(esc "$body")\"}); IO.puts(\"posted ##{m.id} to thread #$tid as #{op}\")"
    ;;

  *)
    echo "usage: mise run funes:{spawn|roster|dossier|post} -- [args]" >&2
    exit 2
    ;;
esac
