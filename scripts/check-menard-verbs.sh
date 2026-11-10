#!/usr/bin/env bash
# The verbs transcript-rows takes for menard's must be the ones menard has: a call of a verb
# missing from the list is drawn as a plain shell row.
set -euo pipefail
menard="${MENARD:-$HOME/projects/menard/bin/menard}"
[ -x "$menard" ] || {
	echo "check-menard-verbs — no menard at $menard, not run"
	exit 0
}
calls="$(dirname "$0")/../modules/agents/mods/transcript-rows/hooks/calls.ts"
ours="$(sed -n "s/^const VERBS = '\(.*\)'.*/\1/p" "$calls" | tr ' ' '\n' | sort)"
theirs="$("$menard" help | sed -n 's/^  \([a-z]\{1,\}\)  .*/\1/p' | sort)"
[ -n "$ours" ] && [ -n "$theirs" ] || {
	echo "check-menard-verbs — could not read both lists"
	exit 1
}
[ "$ours" = "$theirs" ] || {
	echo "check-menard-verbs — calls.ts (<) and menard help (>) differ:"
	diff <(echo "$ours") <(echo "$theirs")
	exit 1
}
