#!/usr/bin/env bash
# funes CLI — operate/script the LIVE channel from the shell (capability-map moves #2/#3):
# the human + Claude Code peer to the agents' MCP tools, and the identity handoff the
# launchers (funes:claude, pi:*) use.
#
# Most subcommands run through `bin/funes rpc` INTO the running service node — a token
# minted anywhere else dies with its node and 401s, and roster/presence is in-memory
# there, so a fresh `eval` node would see neither. The service must be up (the
# `systemd --user` unit, or a dev daemon). EXCEPTION: `token` POSTs to the /mint HTTP
# endpoint at FUNES_MCP_URL's origin, so it mints in the RIGHT world for any node (aleph's
# 4041 or the service's 4040) — bin/funes rpc would only reach the service node and split
# an aleph-handed pane into the wrong world. Thin and deliberate: operate access, NOT a
# second cockpit — aleph is the human's rich surface.
#
# Subcommands:
#   spawn "<title>" <agent>        open a fresh thread, staff+mint, print the export block
#   spawn --join <id> <agent>      JOIN an existing thread instead of opening one
#   token                          headersHelper: mint a FRESH token for (FUNES_THREAD,
#                                  FUNES_AUTHOR) from the env → {"Authorization":"Bearer …"}
#   roster                         who's on the clock (warm ●/cold ○)
#   dossier <id>                   render a thread's brief
#   post <id> <text…>              post as the operator
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
    # Open or join a thread, staff the agent (register if new), and print the identity-only
    # export FUNES_* block (FUNES_MCP_URL / FUNES_THREAD / FUNES_AUTHOR — NO FUNES_TOKEN).
    # The human reads it to paste into a pane; the launchers `eval` it. The adapter mints a
    # fresh token per connect against the URL's /mint (`token`/`bearer` below), so no frozen
    # token strands a pane across a restart, a model change, or a secret regeneration.
    if [ "${1:-}" = "--join" ]; then
      shift; id="${1:-}"; agent="${2:-}"
      { int "$id" && [ -n "$agent" ]; } ||
        { echo 'usage: funes-cli.sh spawn --join <thread-id> <agent-name>' >&2; exit 2; }
      call="Funes.MCP.Spawn.join($id, \"$(esc "$agent")\")"
    else
      title="${1:-}"; agent="${2:-}"
      { [ -n "$title" ] && [ -n "$agent" ]; } ||
        { echo 'usage: mise run funes:spawn -- "<thread title>" <agent-name>' >&2; exit 2; }
      call="Funes.MCP.Spawn.env(\"$(esc "$title")\", \"$(esc "$agent")\")"
    fi
    exec "$FUNES" rpc "{:ok, m} = $call; IO.puts(m.exports)"
    ;;

  token)
    # Claude Code's headersHelper — runs on every MCP connect/reconnect. Output is
    # the exact headers JSON CC merges into the connection. Per-connect /mint → right
    # world, restart-/model-/secret-survival. Any failure exits non-zero so CC reports
    # the server bad.
    tok=$(mint_token) || exit 1
    printf '{"Authorization":"Bearer %s"}
' "$tok"
    ;;
  bearer)
    # pi-mcp-adapter's `!command` header value (runs at connect): same per-connect /mint
    # as `token`, but outputs the BARE `Bearer <token>` value for a header field, not
    # the Claude headersHelper JSON object. Same world-correctness, same survival.
    tok=$(mint_token) || exit 1
    printf 'Bearer %s
' "$tok"
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
    tid="${1:-${FUNES_THREAD:-}}"
    int "$tid" || { echo 'usage: mise run funes:dossier -- <thread-id> (or set FUNES_THREAD)' >&2; exit 2; }
    # The thread's brief — the same Board.in_scope |> Brief.scope the get_dossier MCP
    # tool renders, pretty-printed for the shell (and the Claude Code SessionStart hook).
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
    echo "usage: funes-cli.sh {spawn|token|roster|dossier|post} [args]" >&2
    exit 2
    ;;
esac
