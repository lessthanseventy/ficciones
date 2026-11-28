#!/bin/sh
# plugin-snapshot.sh snapshot CHECKOUT NAME — print the store path of CHECKOUT's plugin files
# (what Claude Code loads, not the build trees) and keep it alive with a GC root. The files are
# those of CHECKOUT's main, the landed ones, so what its working tree holds unlanded is never
# loaded; a checkout with no main gives its working tree.
# plugin-snapshot.sh root NAME STORE_PATH — keep an existing store path alive the same way.
# A session reads CLAUDE_CODE_PLUGIN_DIRS once, at launch, so a copy a running session started
# with must outlive later switches: the newest KEEP roots per NAME stay, the rest are dropped.
set -eu
KEEP=5
roots="${XDG_STATE_HOME:-$HOME/.local/state}/claude-plugin-roots"

root() {
	name=$1 path=$2
	mkdir -p "$roots/$name"
	top=$(printf '%s\n' "$path" | cut -d/ -f1-4)
	link="$roots/$name/$(basename "$top")"
	nix-store --add-root "$link" --indirect --realise "$top" >/dev/null
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
	dirs=".claude-plugin hooks skills commands agents"
	# shellcheck disable=SC2086
	landed=$(git -C "$checkout" ls-tree --name-only main -- $dirs 2>/dev/null || true)
	if [ -n "$landed" ]; then
		# shellcheck disable=SC2086
		git -C "$checkout" archive --format=tar main -- $landed >"$stage/$name.tar"
		tar -xf "$stage/$name.tar" -C "$stage/$name"
	else
		for d in $dirs; do
			[ -e "$checkout/$d" ] && cp -R "$checkout/$d" "$stage/$name/$d"
		done
	fi
	path=$(nix store add --name "$name" "$stage/$name")
	root "$name" "$path"
	printf '%s\n' "$path"
	;;
root) root "$2" "$3" ;;
esac
