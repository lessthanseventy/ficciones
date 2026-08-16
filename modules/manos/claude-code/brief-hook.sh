#!/usr/bin/env bash
# Claude Code SessionStart hook — Door 2 of the claude-code manos adapter (the brief).
#
# On session start/resume/clear, Claude Code adds a command hook's plain stdout to the
# session context. If this session carries a funes identity (FUNES_THREAD, exported by
# `mise run funes:claude`), render that thread's brief — the same Board.in_scope → Brief
# the get_dossier MCP tool serves — so a fresh or /clear'd context re-orients from funes
# instead of from nothing.
#
# It NEVER blocks the session: no funes identity, a down channel, or a missing thread is
# a silent no-op (exit 0, no output). The hook reads its JSON on stdin and ignores it.
set -euo pipefail

thread="${FUNES_THREAD:-}"
[ -n "$thread" ] || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
brief="$("$here/../../../scripts/funes-cli.sh" dossier "$thread" 2>/dev/null || true)"
[ -n "$brief" ] || exit 0

printf '# funes — your thread #%s\n\n%s\n' "$thread" "$brief"
