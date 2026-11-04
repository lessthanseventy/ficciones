#!/usr/bin/env bash
# Keep Claude Code's worktrunk plugin on the tag of the installed wt: upstream's main calls verbs a
# released wt may not have yet, and its WorktreeCreate hook failing breaks isolated worktrees.
set -euo pipefail

tag="v$(wt --version | cut -d' ' -f2)"
known="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/known_marketplaces.json"
[ "$(jq -r '.worktrunk.source.ref // empty' "$known" 2>/dev/null)" = "$tag" ] && exit 0

claude plugin marketplace remove worktrunk >/dev/null 2>&1 || true
claude plugin marketplace add "max-sixty/worktrunk#$tag"
claude plugin install worktrunk@worktrunk --scope user
