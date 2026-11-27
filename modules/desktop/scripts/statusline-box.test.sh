#!/usr/bin/env bash
# The statusline box fits the pane: unchanged at a full width, and at a narrow one every line is
# within the width, ends in the border, and no segment is split.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.claude" "$tmp/run" "$tmp/cfg"
esc=$'\033'

cat >"$tmp/cpl" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '${esc}[0m${esc}[48;2;13;13;13m${esc}[38;2;185;138;255m ~/projects/ficciones ${esc}[0m${esc}[48;2;13;13;13m${esc}[38;2;13;13;13m${esc}[48;2;13;13;13m${esc}[38;2;240;111;182m ⎇ Opus 5.5 ${esc}[0m${esc}[38;2;13;13;13m${esc}[0m'
printf '%s\n' '${esc}[0m${esc}[48;2;13;13;13m${esc}[38;2;51;255;0m ◔ 12% ${esc}[0m${esc}[48;2;13;13;13m${esc}[38;2;51;255;0m ◱ 30% ${esc}[0m${esc}[48;2;13;13;13m${esc}[38;2;51;255;0m ◑ 41% ${esc}[0m${esc}[38;2;13;13;13m${esc}[0m'
EOF
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\ncase "$1" in display) echo "$STUB_WIDTH" ;; esac\n' >"$tmp/bin/tmux"
chmod +x "$tmp/cpl" "$tmp/bin/tmux"
echo '{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":7}]}' >"$tmp/run/claude-usage.json"

render() {
	echo '{"effort":{"level":"medium"},"context_window":{"used_percentage":12}}' |
		env -i PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" XDG_CONFIG_HOME="$tmp/cfg" \
			LANG=en_US.UTF-8 CLAUDE_POWERLINE="$tmp/cpl" "$@" bash "$here/statusline-box.sh" | sed "s/${esc}\[[0-9;?]*[a-zA-Z]//g"
}

bad=0
fail() {
	echo "WRONG  $*"
	bad=1
}

unlimited=$(render)
wide=$(render TMUX_PANE=%1 STUB_WIDTH=120)
[ "$wide" = "$unlimited" ] || fail "120 columns differs from no limit"
[ "$(printf '%s\n' "$wide" | wc -l)" = 4 ] || fail "120 columns is not a two-line box"

narrow=$(render TMUX_PANE=%1 STUB_WIDTH=45)
while IFS= read -r l; do
	[ "${#l}" -le 45 ] || fail "wider than 45: $l"
	case "$l" in *│ | *╮ | *╯) ;; *) fail "no right border: $l" ;; esac
done <<<"$narrow"
for seg in /projects/ficciones '⎇ Opus 5.5' '◆ medium' '󰧑  ctx 12%' '⏱  5h 30%' '▦  wk 41%' '✦  fable 7%'; do
	grep -qF -- "$seg" <<<"$narrow" || fail "segment split or missing: $seg"
done
[ "$(printf '%s\n' "$narrow" | wc -l)" -gt 4 ] || fail "45 columns did not wrap"

# wrapped usage line: ctx/5h in the left column, wk/fable right-aligned in the right one
line_of() { grep -F -- "$1" <<<"$2" | head -1; }
sed -e "s/ ◱ 30% //" "$tmp/cpl" >"$tmp/cpl-no5h"
chmod +x "$tmp/cpl-no5h"
for variant in "$tmp/cpl" "$tmp/cpl-no5h"; do
	out=$(render TMUX_PANE=%1 STUB_WIDTH=45 CLAUDE_POWERLINE="$variant")
	wk=$(line_of '▦  wk' "$out")
	fable=$(line_of '✦  fable' "$out")
	[ -n "$wk" ] && [ -n "$fable" ] || fail "wk or fable line missing ($variant)"
	[ "${#wk}" = "${#fable}" ] || fail "fable line does not end under wk ($variant)"
	case "$fable" in *' '✦*) ;; *) fail "fable is not set off to the right ($variant)" ;; esac
	first=$(sed -n 1p <<<"$out")
	last=$(tail -1 <<<"$out")
	case "$first" in ╭*╮) ;; *) fail "box not closed at top ($variant)" ;; esac
	case "$last" in ╰*╯) ;; *) fail "box not closed at bottom ($variant)" ;; esac
done

tiny=$(render TMUX_PANE=%1 STUB_WIDTH=14)
while IFS= read -r l; do
	[ "${#l}" -le 14 ] || fail "wider than 14: $l"
	case "$l" in *│ | *╮ | *╯) ;; *) fail "no right border at 14: $l" ;; esac
done <<<"$tiny"
grep -q '…' <<<"$tiny" || fail "an overlong segment was not cut with …"

[ "$bad" = 0 ] && echo "ok  statusline box fits the pane"
exit "$bad"
