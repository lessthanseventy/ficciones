#!/usr/bin/env bash
# Rewrites a tmux-resurrect save file without what babylon owns: its orchestrator and gate
# sessions, and its ticket windows (t<id>) in any session.
set -euo pipefail
file=$1
tmp=$(mktemp "$file.XXXXXX")
trap 'rm -f "$tmp"' EXIT
awk -F'\t' -v OFS='\t' '
	function owned(session) { return session == "babylon-gate" || session ~ /^orchestrator(-|$)/ }
	NR == FNR {
		if ($1 == "window") {
			if (owned($2) || $4 ~ /^:t[0-9]+$/) drop[$2, $3] = 1
			else kept[$2] = 1
		}
		next
	}
	# a line of no type is the rest of the pane line before it: a command of several lines
	$1 == "pane" || $1 == "window" { skip = ($2, $3) in drop }
	$1 == "state" {
		skip = 0
		for (i = 2; i <= 3; i++) if (!($i in kept)) $i = ""
	}
	$1 == "grouped_session" { skip = 0 }
	!skip
' "$file" "$file" >"$tmp"
mv "$tmp" "$file"
