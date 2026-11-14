#!/usr/bin/env bash
# what modules/agents/session.sh sets and briefs
cmd="$(cd "$(dirname "$0")" && pwd)/session.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run/sessions"
# the panes tmux has: a crashed session's %9 is not among them
cat >"$work/bin/tmux" <<'EOF2'
#!/usr/bin/env bash
case $2 in /s) printf '/s %%1\n/s %%2\n/s %%3\n/s %%4\n' ;; esac
EOF2
chmod +x "$work/bin/tmux"
export PATH="$work/bin:$PATH" XDG_RUNTIME_DIR="$work/run" TMUX_PANE=%1
now=$(date +%s)
rec() { jq -n --arg id "$1" --arg repo "$2" --arg state "$3" --arg pane "$4" --arg sock "${5:-/s}" --argjson at "$now" \
	'{id: $id, repo: $repo, state: $state, pane: $pane, socket: $sock, since: ($at - 300), at: $at, said: "the ask", doing: "Edit x.ex"}' \
	>"$work/run/sessions/$1.json"; }
rec aaaa1111 arena working %1
rec bbbb2222 menard "done" %2
rec cccc3333 menard idle %3
rec dddd4444 tlon waiting %4 /tmp/tlon-workspace-x
rec eeee5555 gone "done" %9
bad=0
claim() {
	local what=$1
	shift
	if "$@"; then echo "ok    $what"; else
		echo "WRONG $what"
		bad=1
	fi
}
field() { jq -r ".$2" "$work/run/sessions/$1.json"; }

bash "$cmd" set goal "ship the brief"
claim "set with no one named is this pane's session" test "$(field aaaa1111 goal)" = "ship the brief"
bash "$cmd" set next "wire the hook" arena
claim "a repo names a session" test "$(field aaaa1111 next)" = "wire the hook"
bash "$cmd" set next "x" menard 2>"$work/err"
claim "a repo with two sessions is refused" test $? = 1 -a "$(field bbbb2222 next)" = null
claim "and says which ids" grep -q "bbbb2222 cccc3333" "$work/err"
bash "$cmd" set next "review it" bbbb
claim "the start of an id names one" test "$(field bbbb2222 next)" = "review it"
bash "$cmd" set next "" arena
claim "an empty text clears it" test "$(field aaaa1111 next)" = null
bash "$cmd" set mood "x" 2>/dev/null
claim "only goal and next are set" test $? = 1

out=$(bash "$cmd" brief)
want="your move
  menard bbbb2222  done 5m
    next  review it
    said  the ask

running
  arena aaaa1111  working 5m
    goal  ship the brief
    doing Edit x.ex

parked
  menard cccc3333  idle 5m
    said  the ask"
claim "the brief groups them, your move first" test "$out" = "$want"
[ "$out" = "$want" ] || diff <(echo "$want") <(echo "$out")
claim "and leaves out the crew and the crashed" test -z "$(grep -E 'tlon|gone' <<<"$out")"
exit $bad
