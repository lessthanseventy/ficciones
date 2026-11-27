#!/usr/bin/env bash
# Bring arena forward on what needs the human. Arena's own verb picks the item; with no arena
# running it exits 3 and the caller opens one.
arena inbox
case $? in
0) exec hyprctl dispatch 'hl.dsp.focus({ window = "class:^com.ghostty.arena$" })' ;;
3) exec ghostty --title=arena --class=com.ghostty.arena -e arena inbox ;;
esac
