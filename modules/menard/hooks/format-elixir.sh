#!/usr/bin/env bash
# PostToolUse hook: format an Elixir file the moment it is written, with ITS OWN project's
# formatter — the .formatter.exs found by walking up to the nearest mix.exs, plugins included
# (console runs Styler, which rewrites code, not just whitespace).
#
# Why on write and not at the gate: every format failure this repo has seen came from a file
# written without running the formatter at all, then discovered minutes later at `mix format
# --check-formatted`, with the diff moving under whoever was editing. Formatting here means the
# formatter's output IS what the next read shows, so there is nothing left to discover.
#
# Reads the PostToolUse payload on stdin. Never fails the tool call: a formatter error leaves the
# file exactly as written and the gate still catches it.
set -uo pipefail

file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -n "$file" ]] || exit 0

case "$file" in
  *.ex | *.exs) ;;
  *) exit 0 ;;
esac

[[ -f "$file" ]] || exit 0

# The formatter's config lives at the project root, not beside the file; run mix from there or it
# silently falls back to the default line length and reflows the whole file.
dir=$(dirname "$(readlink -f "$file")")
while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do
  dir=$(dirname "$dir")
done
[[ -f "$dir/mix.exs" ]] || exit 0

(cd "$dir" && mix format "$file") >/dev/null 2>&1 || true
exit 0
