#!/usr/bin/env bash
# modules/agents/menard-scope.sh allows menard edit/write inside a ticket worktree and nowhere else
hook="$(cd "$(dirname "$0")" && pwd)/menard-scope.sh"
export HOME=/home/t
bad=0
run() { jq -nc --arg cwd "$1" "{cwd: \$cwd, tool_input: $2}" | bash "$hook"; }
expect() {
	local want=$1 what=$2 got
	got=$(run "$3" "$4" | jq -r ".hookSpecificOutput.permissionDecision")
	got=${got:-none}
	if [ "$got" = "$want" ]; then echo "ok    $what"; else
		echo "WRONG $what: $got"
		bad=1
	fi
}
wt=/home/t/projects/r/.worktrees/t1
expect allow "relative edit in a worktree" $wt '{edits: [{file: "lib/a.ex"}]}'
expect allow "absolute write in a worktree" /x "{file: \"$wt/a.ex\"}"
expect allow "babylon work dir" /x '{edits: [{file: "/home/t/.cache/babylon/work/t2/a.ex"}]}'
expect none "main checkout" /home/t/projects/r '{edits: [{file: "lib/a.ex"}]}'
expect none "dotfile" $wt '{edits: [{file: "/home/t/.zshrc"}]}'
expect none "dotdot escape" $wt '{edits: [{file: "../../../lib/a.ex"}]}'
expect none "one bad file among good" $wt "{edits: [{file: \"a.ex\"}, {file: \"/etc/hosts\"}]}"
expect none "no path at all" $wt '{}'
exit $bad
