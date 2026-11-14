#!/usr/bin/env bash
# The Claude sessions' records that ./session-state.sh keeps in $XDG_RUNTIME_DIR/sessions.
#   session set goal|next TEXT [WHO]  WHO is a repo or the start of an id; left out, this pane's session
#   session brief                     your sessions, the ones that are your move first
dir="${XDG_RUNTIME_DIR:-/tmp}/sessions"
die() {
	echo "session: $*" >&2
	exit 1
}

# every record of yours whose pane is still there: a crash leaves its record behind
records() {
	local live='' sock
	for sock in $(cat "$dir"/*.json 2>/dev/null | jq -r '.socket // empty' | sort -u); do
		live+=$(tmux -S "$sock" list-panes -a -F "$sock #{pane_id}" 2>/dev/null)$'\n'
	done
	cat "$dir"/*.json 2>/dev/null | jq -s --arg live "$live" '($live | split("\n")) as $l
		| map(select((.socket // "" | test("/tlon-workspace-[^/]*$")) | not)
			| select(.pane == "" or ("\(.socket) \(.pane)" as $k | $l | index($k))))'
}

set_field() {
	local key=$1 text=$2 who=${3:-} ids
	case $key in goal | next) ;; *) die "set goal or next, not '$key'" ;; esac
	if [ -n "$who" ]; then
		ids=$(records | jq -r --arg w "$who" '.[] | select(.repo == $w or (.id | startswith($w))) | .id')
	else
		[ -n "${TMUX_PANE:-}" ] || die "not in tmux: name the session"
		ids=$(records | jq -r --arg p "$TMUX_PANE" 'map(select(.pane == $p)) | max_by(.at) | .id // empty')
	fi
	[ -n "$ids" ] || die "no session ${who:-in pane $TMUX_PANE}"
	[ "$(wc -l <<<"$ids")" = 1 ] || die "'$who' is $(tr '\n' ' ' <<<"$ids")— name one by its id"
	local file="$dir/$ids.json" tmp
	tmp=$(mktemp "$dir/.$ids.XXXXXX") || die "cannot write in $dir"
	if jq --arg k "$key" --arg v "$text" '.[$k] = (if $v == "" then null else $v end)' "$file" >"$tmp"; then
		mv -f "$tmp" "$file"
	else
		rm -f "$tmp"
		die "cannot set $key on $ids"
	fi
}

brief() {
	records | jq -r --argjson now "$(date +%s)" '
		def age: ($now - .since) as $s
			| if $s < 60 then "\($s)s" elif $s < 3600 then "\($s / 60 | floor)m"
			  elif $s < 86400 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end;
		def row: "  \(.repo) \(.id[:8])  \(.state) \(age)"
			+ (if .goal then "\n    goal  \(.goal)" else "" end)
			+ (if .next then "\n    next  \(.next)" else "" end)
			+ (if .state == "working" and .doing then "\n    doing \(.doing)"
			   elif .said then "\n    said  \(.said)" else "" end);
		def group($title; $states): map(select(.state as $s | $states | index($s))) | sort_by(.repo)
			| if length == 0 then empty else "\($title)\n" + (map(row) | join("\n")) end;
		if length == 0 then "no sessions" else
		[group("your move"; ["waiting", "done"]), group("running"; ["working"]), group("parked"; ["idle"])]
			| join("\n\n") end'
}

case ${1:-} in
set) set_field "${2:-}" "${3:-}" "${4:-}" ;;
brief) brief ;;
*) die "usage: session set goal|next TEXT [WHO] | session brief" ;;
esac
