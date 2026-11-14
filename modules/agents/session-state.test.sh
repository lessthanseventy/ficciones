#!/usr/bin/env bash
# every record and pane mark modules/agents/session-state.sh should leave
hook="$(cd "$(dirname "$0")" && pwd)/session-state.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run" "$work/repo/lib"
git -C "$work/repo" init -q
cat >"$work/bin/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/tmux.log"
EOF
chmod +x "$work/bin/tmux"
export PATH="$work/bin:$PATH" XDG_RUNTIME_DIR="$work/run" TMUX="/tmp/tmux-1000/default,1,0" TMUX_PANE=%7
rec="$work/run/sessions/s1.json"
bad=0
send() { jq -nc --arg cwd "$work/repo/lib" "{session_id: \"s1\", cwd: \$cwd} + $2" | bash "$hook" "$1"; }
is() {
	got=$(jq -r "$1" "$rec" 2>/dev/null)
	v=ok
	[ "$got" = "$2" ] || {
		v=WRONG
		bad=1
	}
	printf '%-5s %-12s = %-28s %s\n' "$v" "$1" "$got" "$3"
}
claim() {
	local what=$1
	shift
	if "$@"; then echo "ok    $what"; else
		echo "WRONG $what"
		bad=1
	fi
}

send prompt '{prompt: "make   the bar\nknow about my sessions"}'
is .state working "a prompt starts work"
is .repo repo "the repo is the git top, not the cwd"
is .socket /tmp/tmux-1000/default "the tmux socket"
is .pane %7 "and the pane"
is .said "make the bar know about my sessions" "what was asked, on one line"
since=$(jq .since "$rec")

send tool '{tool_name: "Edit", tool_input: {file_path: "/r/lib/deck.ex", old_string: "a"}}'
is .doing "Edit deck.ex" "a file call names the file"
is .since "$since" "staying at work keeps since"
send tool '{tool_name: "Bash", tool_input: {command: "ls", description: "List files"}}'
is .doing "List files" "a description wins"
send tool '{tool_name: "TodoWrite", tool_input: {todos: []}}'
is .doing TodoWrite "else the tool"

send waiting '{notification_type: "permission_prompt"}'
is .state waiting "a permission prompt waits on you"
is .doing TodoWrite "and keeps what it was doing"
send stop '{background_tasks: [{status: "running"}]}'
is .state working "a stop with work in the background is still at work"
send stop '{background_tasks: [{status: "completed"}]}'
is .state "done" "a stop with nothing running is done"
is .said "make the bar know about my sessions" "the ask outlives the turn"

echo '{"session_id": "../x"}' | bash "$hook" tool
claim "a session id cannot leave the dir" test ! -e "$work/run/x.json"
echo 'not json' | bash "$hook" tool
claim "bad input exits 0" test $? = 0

want="set -p -t %7 @arena_claude working|set -p -t %7 @arena_claude working|set -p -t %7 @arena_claude working|set -p -t %7 @arena_claude working|set -p -t %7 @arena_claude waiting|set -p -t %7 @arena_claude working|set -p -t %7 @arena_claude done|"
claim "arena's pane marks follow the state" test "$(tr '\n' '|' <"$work/tmux.log")" = "$want"

send end '{}'
claim "the end removes the record" test ! -e "$rec"
claim "and unmarks the pane" test "$(tail -1 "$work/tmux.log")" = "set -pu -t %7 @arena_claude"
exit $bad
