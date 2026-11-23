#!/usr/bin/env bash
# PreToolUse hook for menard's edit and write: allow only when every target path is inside a
# ticket worktree; anything else prints nothing, so the normal permission prompt decides.
# A relative path never passes: menard resolves it from its own shell directory, not the payload cwd.
in=$(cat)
files=$(jq -r '[.tool_input.file?, .tool_input.path?, (.tool_input.edits[]?.file?)] | map(select(type == "string")) | .[]' <<<"$in")
[ -n "$files" ] || exit 0
while IFS= read -r f; do
	case "$f" in
	/*) ;;
	*) exit 0 ;;
	esac
	f=$(realpath -m -- "$f")
	case "$f" in
	"$HOME"/projects/*/.worktrees/?*/* | "$HOME"/.cache/babylon/work/?*/*) ;;
	*) exit 0 ;;
	esac
done <<<"$files"
jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "inside a ticket worktree"}}'
