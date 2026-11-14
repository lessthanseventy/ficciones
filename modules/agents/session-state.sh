#!/usr/bin/env bash
# A Claude Code hook. $1 is the event (prompt | tool | stop | waiting | end), the hook's JSON is on
# stdin. It keeps the session's record at $XDG_RUNTIME_DIR/sessions/<session_id>.json, which the
# desktop shell reads, and the pane option @arena_claude arena marks the window by.
# A hook must never fail a turn: every miss is silent and the exit is 0.
event=${1:-}
input=$(cat)
dir="${XDG_RUNTIME_DIR:-/tmp}/sessions"
id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
case $id in "" | */* | .*) exit 0 ;; esac
file="$dir/$id.json"
pane=${TMUX_PANE:-}

if [ "$event" = end ]; then
	rm -f "$file" "$dir/$id.meter"
	[ -z "$pane" ] || tmux set -pu -t "$pane" @arena_claude 2>/dev/null
	exit 0
fi

case $event in
stop) state=$(jq -r 'if any(.background_tasks[]?; .status == "running") then "working" else "done" end' <<<"$input") ;;
waiting) state=waiting ;;
*) state=working ;;
esac
[ -z "$pane" ] || tmux set -p -t "$pane" @arena_claude "$state" 2>/dev/null

cwd=$(jq -r '.cwd // empty' <<<"$input")
top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || top=$cwd
prev=$(jq -c . "$file" 2>/dev/null)
[ -n "$prev" ] || prev='{}'
[ -d "$dir" ] || mkdir -m 700 "$dir" 2>/dev/null
tmp=$(mktemp "$dir/.$id.XXXXXX") || exit 0
if jq --argjson prev "$prev" --arg event "$event" --arg state "$state" \
	--arg repo "${top##*/}" --arg socket "${TMUX%%,*}" --arg pane "$pane" --argjson now "$(date +%s)" '
	def short: gsub("\\s+"; " ") | if length > 72 then .[:71] + "…" else . end;
	def doing: (.tool_input // {}) as $t | .tool_name as $tool
		| if $t.description then $t.description
			elif $t.file_path then "\($tool) \($t.file_path | sub(".*/"; ""))"
			elif ($t.pattern // $t.url // $t.command) then "\($tool) \($t.pattern // $t.url // $t.command)"
			else $tool end | tostring | short;
	. as $in | { id: $in.session_id, state: $state,
	  since: (if $prev.state == $state then $prev.since else $now end),
	  at: $now, cwd: $in.cwd, repo: $repo, socket: $socket, pane: $pane,
	  said: (if $event == "prompt" then ($in.prompt // "" | short) else $prev.said end),
	  doing: (if $event == "tool" then ($in | doing) elif $event == "prompt" then null else $prev.doing end) }
	' >"$tmp" 2>/dev/null <<<"$input"; then
	mv -f "$tmp" "$file"
else
	rm -f "$tmp"
fi
exit 0
