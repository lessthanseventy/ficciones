#!/usr/bin/env bash
# what modules/agents/session.sh sets and briefs
cmd="$(cd "$(dirname "$0")" && pwd)/session.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run/sessions"
# the panes tmux has: a crashed session's %9 is not among them
cat >"$work/bin/tmux" <<'EOF2'
#!/usr/bin/env bash
case $2 in /s) printf '/s %%1\n/s %%2\n/s %%3\n/s %%4\n' ;; /other) printf '/other %%1\n' ;; esac
EOF2
chmod +x "$work/bin/tmux"
export PATH="$work/bin:$PATH" XDG_RUNTIME_DIR="$work/run" TMUX_PANE=%1 TMUX=/s,1,0
now=$(date +%s)
rec() { jq -n --arg id "$1" --arg repo "$2" --arg state "$3" --arg pane "$4" --arg sock "${5:-/s}" --argjson at "$now" \
	'{id: $id, repo: $repo, state: $state, pane: $pane, socket: $sock, since: ($at - 300), at: $at, said: "the ask", doing: "Edit x.ex"}' \
	>"$work/run/sessions/$1.json"; }
rec aaaa1111 arena working %1
rec bbbb2222 menard "done" %2
rec cccc3333 menard idle %3
rec dddd4444 tlon stalled %4
rec eeee5555 gone "done" %9
rec gggg7777 headless "done" ""
jq --arg c "$work/vanished" '.cwd = $c' "$work/run/sessions/gggg7777.json" >"$work/g" && mv "$work/g" "$work/run/sessions/gggg7777.json"
rec hhhh8888 headlive "done" ""
jq --arg c "$work" '.cwd = $c' "$work/run/sessions/hhhh8888.json" >"$work/g" && mv "$work/g" "$work/run/sessions/hhhh8888.json"
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

# another tmux server's %1, written later
rec ffff6666 other working %1 /other
jq '.at += 60' "$work/run/sessions/ffff6666.json" >"$work/f" && mv "$work/f" "$work/run/sessions/ffff6666.json"
bash "$cmd" set goal "ship the brief"
claim "set with no one named is this pane's session" test "$(field aaaa1111 goal)" = "ship the brief"
claim "and not the same pane id on another server" test "$(field ffff6666 goal)" = null
rm "$work/run/sessions/ffff6666.json"
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
want="stalled
  tlon dddd4444  stalled 5m
    said  the ask

your move
  headlive hhhh8888  done 5m
    said  the ask
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
claim "the brief groups them, the stalled first, then your move" test "$out" = "$want"
[ "$out" = "$want" ] || diff <(echo "$want") <(echo "$out")
claim "and leaves out the crashed" test -z "$(grep gone <<<"$out")"
claim "and a paneless record whose cwd is gone, keeping one whose cwd exists" test -z "$(grep headless <<<"$out")"
exit $bad
