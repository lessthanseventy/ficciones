#!/usr/bin/env bash
# PreToolUse hook: an Elixir module is edited with menard's verbs, not with Edit/Write or a
# sed/python one-liner. The verbs parse the file, change the tree and parse-check the result, so a
# half-applied edit is impossible; a text substitution is a guess that is right most of the time,
# and the times it is wrong are silent.
#
# A rule the agent has to remember is a rule it breaks, which is the argument for a hook rather
# than a note in AGENTS.md. Blocks (exit 2) and names the verb to use instead.
#
# Scope, deliberately narrow so it never blocks legitimate work:
#   - only .ex/.exs files that actually hold a `defmodule` (menard's domain)
#   - never new files, _build/, deps/, or the bare-data .exs (config/, .formatter.exs, mix.lock)
#
# Edit/Write only, NOT Bash. A shell command carries no structured target, so deciding whether it
# writes to an Elixir file means pattern-matching the command text — and that fires on a command
# that merely QUOTES the pattern (a test, a grep for `sed -i`, a heredoc showing the wrong way).
# A guard that blocks innocent commands is worse than no guard. `sed -i` on a module is still
# wrong; it is AGENTS.md's job to say so, not this hook's job to guess.
set -uo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null) || exit 0

exempt() { # bare-data .exs and anything generated: menard has no verbs for a keyword list
  case "$1" in
    */_build/* | */deps/* | */config/*.exs | */.formatter.exs | */mix.lock) return 0 ;;
    *) return 1 ;;
  esac
}

# However menard is reachable from here: its own bin, a mise task, or the PATH.
menard_cmd() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -x "$CLAUDE_PLUGIN_ROOT/bin/menard" ]]; then
    echo "$CLAUDE_PLUGIN_ROOT/bin/menard"
  elif [[ -f "${CLAUDE_PROJECT_DIR:-.}/modules/menard/tasks.toml" ]]; then
    echo "mise run menard --"
  elif command -v menard >/dev/null 2>&1; then
    echo "menard"
  else
    echo "menard"
  fi
}

deny() {
  local m
  m=$(menard_cmd)
  cat >&2 <<MSG
Blocked: $1

An Elixir module is edited with menard's verbs — they parse the file, change the tree and
parse-check what they write — not with text substitution:

  $m outline FILE                        what is in the file
  $m attr get|set|delete FILE NAME [VAL]  a module attribute
  $m clause replace|rewrite|delete|insert-after FILE name/arity HEAD [CODE]
  $m stmt insert-after|replace|delete FILE name/arity HEAD MATCH [CODE]
  $m block get|replace|add FILE NAME [CODE]
  $m rename OLD NEW [--atoms] [--comments] FILES

If this file genuinely is not a module (a plain script, a data .exs), say so and edit it
directly — do not reach for a different write idiom to get around this.
MSG
  exit 2
}

case "$tool" in
  Edit | MultiEdit | Write | NotebookEdit)
    file=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)
    [[ -n "$file" ]] || exit 0
    case "$file" in *.ex | *.exs) ;; *) exit 0 ;; esac
    exempt "$file" && exit 0
    # a file that does not exist yet is a creation, and menard write is not the only honest way
    [[ -f "$file" ]] || exit 0
    grep -q '^[[:space:]]*defmodule' "$file" 2>/dev/null || exit 0
    deny "$tool on $file — an Elixir module."
    ;;
esac
exit 0
