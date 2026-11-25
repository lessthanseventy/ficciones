#!/bin/sh
# plugin-snapshot.sh snapshot CHECKOUT NAME — print the store path of CHECKOUT's plugin files
# (what Claude Code loads, not the build trees) and keep it alive with a GC root.
# plugin-snapshot.sh root NAME STORE_PATH — keep an existing store path alive the same way.
# A session reads CLAUDE_CODE_PLUGIN_DIRS once, at launch, so a copy a running session started
# with must outlive later switches: the newest KEEP roots per NAME stay, the rest are dropped.
set -eu
KEEP=5
roots="${XDG_STATE_HOME:-$HOME/.local/state}/claude-plugin-roots"

root() {
	name=$1 path=$2
	mkdir -p "$roots/$name"
	link="$roots/$name/$(basename "$path")"
	nix-store --add-root "$link" --indirect --realise "$path" >/dev/null
	touch -h "$link"
	# shellcheck disable=SC2012
	ls -t "$roots/$name" | tail -n +$((KEEP + 1)) | while read -r old; do rm -f "$roots/$name/$old"; done
}

case "$1" in
snapshot)
	checkout=$2 name=$3
	stage=$(mktemp -d)
	trap 'rm -rf "$stage"' EXIT
	mkdir "$stage/$name"
	for d in .claude-plugin hooks skills commands agents; do
		[ -e "$checkout/$d" ] && cp -R "$checkout/$d" "$stage/$name/$d"
	done
	path=$(nix store add --name "$name" "$stage/$name")
	root "$name" "$path"
	printf '%s\n' "$path"
	;;
root) root "$2" "$3" ;;
esac
