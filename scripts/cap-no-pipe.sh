#!/usr/bin/env bash
# PreToolUse hook: refuses cap piped into a filter. cap already captures stderr and clips what it
# prints, and a filter only hides what the log holds. Exit 2 is how a hook refuses a call.
set -uo pipefail

# quoted text is an argument, not a pipe; || and 2>&1 are not pipes either
stripped="$(jq -r '.tool_input.command // ""' |
	sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g; s/2>&1//g; s/\|\|/ ; /g")"

if printf '%s\n' "$stripped" |
	grep -qE '(^|[;&|(])[[:space:]]*([A-Za-z_]+=[^[:space:]]*[[:space:]]+)*((ba)?sh[[:space:]]+)?([^[:space:];&|]*cap\.sh|mise run cap)[[:space:]][^|;&]*\|'; then
	echo "cap already captures stderr and clips long lines: run it bare, then grep or tail the log it names. CAP_TAIL, CAP_SIGNAL and CAP_WIDTH set how much it prints." >&2
	exit 2
fi
