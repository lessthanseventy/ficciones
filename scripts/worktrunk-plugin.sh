#!/usr/bin/env bash
# Keep Claude Code's worktrunk plugin on the tag of the installed wt: upstream's main calls verbs a
# released wt may not have yet, and its WorktreeCreate hook failing breaks isolated worktrees.
set -euo pipefail

tag="v$(wt --version | cut -d' ' -f2)"
known="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/known_marketplaces.json"
[ "$(jq -r '.worktrunk.source.ref // empty' "$known" 2>/dev/null)" = "$tag" ] && exit 0

# the remove below cannot be undone offline: leave the working plugin alone until the tag is reachable
git ls-remote --exit-code https://github.com/max-sixty/worktrunk "refs/tags/$tag" >/dev/null 2>&1 || {
	echo "worktrunk-plugin: $tag not reachable on GitHub, plugin left as it is" >&2
	exit 0
}
claude plugin marketplace remove worktrunk >/dev/null 2>&1 || true
claude plugin marketplace add "max-sixty/worktrunk#$tag"
claude plugin install worktrunk@worktrunk --scope user
