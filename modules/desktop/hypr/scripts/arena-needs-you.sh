#!/usr/bin/env bash
# Bring arena forward on what needs the human. `arena inbox` only tells a running arena and
# exits 3 when there is none; a plain `arena` opens home, where Your move comes first.
arena inbox
rc=$?
case $rc in
0) exec hyprctl dispatch 'hl.dsp.focus({ window = "class:^com.ghostty.arena$" })' ;;
3) exec ghostty --title=arena --class=com.ghostty.arena -e arena ;;
*) exec notify-send "arena inbox failed" "exit $rc" ;;
esac
