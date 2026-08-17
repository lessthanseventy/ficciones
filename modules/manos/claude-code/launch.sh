#!/usr/bin/env bash
# mise run funes:claude [thread-id] — launch Claude Code as a funes citizen.
# No thread-id: open a fresh thread. A numeric thread-id: join that thread (resume across
# a /clear).
#
# The funes MCP server (Door 1) and brief hook (Door 2) are scoped to THIS session via
# `--mcp-config`/`--settings`, not installed into ~/.claude, so a normal `claude` stays
# untouched.
#
# The token is never frozen: the MCP server's `headersHelper` mints a fresh token per
# connect/reconnect (POST /mint at FUNES_MCP_URL's origin), so auth survives a funes
# restart, a token-model change, or a secret regeneration.
set -euo pipefail

adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$adapter/../../.." && pwd)"
cli="$repo/scripts/funes-cli.sh"

# If the environment already carries a funes identity (e.g. aleph's Tlön pane exported it
# before exec'ing this launcher), keep it as-is — per-connect minting targets FUNES_MCP_URL's
# origin, so the token is always minted in the same world that serves /mcp.
if [ -z "${FUNES_MCP_URL:-}" ] || [ -z "${FUNES_THREAD:-}" ] || [ -z "${FUNES_AUTHOR:-}" ]; then
  # Optional leading numeric thread-id → join; otherwise open a fresh thread.
  join_id=""
  if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    join_id="$1"
    shift
  fi

  if [ -n "$join_id" ]; then
    block="$("$cli" spawn --join "$join_id" claude-code 2>/dev/null || true)"
  else
    branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
    block="$("$cli" spawn "claude-code @ $(basename "$PWD")${branch:+ ($branch)}" claude-code 2>/dev/null || true)"
  fi

  # Degrade gracefully: no live channel (or no such thread) → launch a PLAIN claude, so
  # the harness is never held hostage to funes being up.
  if [ -z "$block" ]; then
    echo "funes: channel not up${join_id:+ or no thread #$join_id} — launching plain claude (start it with 'mise run funes:restart')" >&2
    [ "${FUNES_LAUNCH_DRYRUN:-}" = "1" ] && { echo "exec: claude $*"; exit 0; }
    exec claude "$@"
  fi
  eval "$block" # exports FUNES_MCP_URL / FUNES_THREAD / FUNES_AUTHOR (no FUNES_TOKEN — minted per connect)
fi

mcp_json="{\"mcpServers\":{\"funes\":{\"type\":\"http\",\"url\":\"$FUNES_MCP_URL\",\"headersHelper\":\"$cli token\"}}}"
settings_json="{\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/brief-hook.sh\"}]}]}}"

if [ "${FUNES_LAUNCH_DRYRUN:-}" = "1" ]; then
  printf 'identity: FUNES_THREAD=%s FUNES_AUTHOR=%s\n' "$FUNES_THREAD" "$FUNES_AUTHOR"
  printf 'mcp-config: %s\n' "$mcp_json"
  printf 'settings:   %s\n' "$settings_json"
  printf 'exec: claude --mcp-config <…> --settings <…> %s\n' "$*"
  exit 0
fi

exec claude --mcp-config "$mcp_json" --settings "$settings_json" "$@"