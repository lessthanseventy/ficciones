#!/usr/bin/env bash
# sandbox-sweep ROOT... — removes the 0-byte read-only files Claude Code's sandbox makes as mount
# points for protected paths that do not exist (.git/config.lock, .mcp.json, .claude/*, shell rcs).
# The sandbox removes them only when a command ends; a session killed mid-command (any signal)
# leaves them, and a stale .git/config.lock refuses every `git config` write.
# Kept: anything a live sandbox still has mounted (any process's mountinfo), anything git tracks,
# and anything younger than a minute, so a sandbox that is starting is not raced.
set -u

# shellcheck disable=SC2086 # the default is a glob over every process
mounted=$(cat ${SANDBOX_SWEEP_MOUNTINFO:-/proc/[0-9]*/mountinfo} 2>/dev/null | cut -d' ' -f5 | sort -u)

find "$@" -maxdepth 7 \( -name node_modules -o -name _build -o -name deps -o -name objects -o -name target \) -prune -o \
	-type f -size 0 ! -perm -u+w -mmin +1 \( \
	-name .bash_profile -o -name .bashrc -o -name .profile -o -name .zprofile -o -name .zshrc \
	-o -name .gitconfig -o -name .gitmodules -o -name .ripgreprc -o -name .idea -o -name .vscode -o -name .mcp.json \
	-o \( -path '*/.claude/*' ! -path '*/.claude/*/*' \) \
	-o \( -path '*/.git/*' -name '*.lock' \) \
	\) -print0 2>/dev/null |
	while IFS= read -r -d '' f; do
		grep -qxF -- "${f// /\\040}" <<<"$mounted" && continue
		git -C "$(dirname "$f")" ls-files --error-unmatch -- "$(basename "$f")" >/dev/null 2>&1 && continue
		rm -f -- "$f" && echo "removed $f"
	done
