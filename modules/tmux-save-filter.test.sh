#!/usr/bin/env bash
# tmux-save-filter.sh keeps the human's sessions and windows and drops babylon's
filter="$(cd "$(dirname "$0")" && pwd)/tmux-save-filter.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
row() { (IFS=$'\t' && printf '%s\n' "$*"); }
pane() { row pane "$1" "$2" 0 : 1 title ":/home/me" 1 "$3" ":$4"; }
window() { row window "$1" "$2" ":$3" 0 : layout off; }

{
	pane mine 1 zsh ""
	pane mine 2 nvim "nvim notes.md"
	pane ficciones 1 zsh ""
	pane ficciones 2 claude "beam.smp -root /x"
	echo "npm exec something"
	pane ficciones 3 zsh ""
	pane menard 1 claude "beam.smp"
	echo "npm exec something"
	pane babylon-gate 1 sh "sh -c mise run check"
	echo "tee /log"
	pane orchestrator 1 claude "beam.smp"
	pane orchestrator-arena 1 claude "beam.smp"
	pane orchestra 1 zsh ""
	window mine 1 zsh
	window mine 2 t12x
	window ficciones 1 zsh
	window ficciones 2 t1715
	window ficciones 3 notes
	window menard 1 t1686
	window babylon-gate 1 ficciones
	window orchestrator 1 claude
	window orchestrator-arena 1 claude
	window orchestra 1 zsh
	row state orchestrator mine
} >"$work/save"

{
	pane mine 1 zsh ""
	pane mine 2 nvim "nvim notes.md"
	pane ficciones 1 zsh ""
	pane ficciones 3 zsh ""
	pane orchestra 1 zsh ""
	window mine 1 zsh
	window mine 2 t12x
	window ficciones 1 zsh
	window ficciones 3 notes
	window orchestra 1 zsh
	row state "" mine
} >"$work/want"

"$filter" "$work/save" || {
	echo "WRONG: the filter failed"
	exit 1
}
if diff "$work/want" "$work/save"; then
	echo "ok    hand-made sessions and windows kept; orchestrator, gate and ticket windows gone"
else
	echo "WRONG: the filtered save is not what was wanted (diff above: < wanted, > got)"
	exit 1
fi
[ "$(find "$work" -type f | wc -l)" = 2 ] || {
	echo "WRONG: the filter left a file behind"
	exit 1
}
echo "ok    no temporary file left"
