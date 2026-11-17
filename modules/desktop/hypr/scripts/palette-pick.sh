#!/usr/bin/env bash
# Pick a colour of the live palette by name: Enter copies its hex, Ctrl-R its rgb().
set -euo pipefail
palette="${XDG_CONFIG_HOME:-$HOME/.config}/ficciones/palette.sh"
rows=""
while IFS='=' read -r key hex; do
	r=$((16#${hex:1:2})) g=$((16#${hex:3:2})) b=$((16#${hex:5:2}))
	name=$(tr '[:upper:]' '[:lower:]' <<<"${key#PALETTE_}")
	rows+=$(printf '\e[48;2;%d;%d;%dm      \e[0m %-12s %s\trgb(%d, %d, %d)' "$r" "$g" "$b" "$name" "$hex" "$r" "$g" "$b")$'\n'
done < <(grep -E '^PALETTE_[A-Z0-9]+=#[0-9A-Fa-f]{6}$' "$palette")

out=$(printf '%s' "$rows" | fzf --ansi --delimiter=$'\t' --expect=ctrl-r --prompt='colour> ' \
	--header='enter: hex · ctrl-r: rgb') || exit 0
key=$(head -n1 <<<"$out")
line=$(sed -n 2p <<<"$out")
if [[ "$key" == ctrl-r ]]; then
	value=${line#*$'\t'}
else
	value=$(awk -F'\t' '{ n = split($1, f, " "); print f[n] }' <<<"$line")
fi
printf '%s' "$value" | wl-copy
