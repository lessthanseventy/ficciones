#!/usr/bin/env bash
# every verdict scripts/cap-no-pipe.sh should reach
hook="$(dirname "$0")/cap-no-pipe.sh"
bad=0
try() {
	want=$1
	cmd=$2
	jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$hook" >/dev/null 2>&1
	rc=$?
	[ "$rc" = "$want" ] && v=ok || {
		v=WRONG
		bad=1
	}
	printf '%-5s rc=%s  %s\n' "$v" "$rc" "$cmd"
}
try 2 'scripts/cap.sh mise run check | tail -3'
try 2 'scripts/cap.sh mise run check 2>&1 | sed -n 1,5p'
try 2 'cd x; ~/projects/ficciones/scripts/cap.sh mix test | rg FAIL'
try 2 'mise run cap -- mix test | head'
try 2 'bash scripts/cap.sh foo |& cut -c1-100'
try 0 'scripts/cap.sh mise run check'
try 0 'scripts/cap.sh mise run check; git log | head -3'
try 0 'scripts/cap.sh mise run check && git log | head -3'
try 0 'scripts/cap.sh mise run check || git log | head -3'
try 0 "scripts/cap.sh elixir -e 'a |> b | c'"
try 0 'scripts/cap.sh bash -c "ls | wc -l"'
try 0 'git log | head -3'
try 0 'rg cap.sh AGENTS.md | head'
exit $bad
