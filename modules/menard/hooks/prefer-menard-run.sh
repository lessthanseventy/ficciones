#!/usr/bin/env bash
# PostToolUse hook: a bare `mix test` prints a wall of text an agent then greps; `menard run test`
# answers in one structured line — exit, counts, and each failure with its source. The verb was
# documented and got skipped anyway, so the reminder arrives at the moment instead.
#
# Advisory, never blocking: the command has already run and its output stands. That is what lets
# the match stay loose — a false positive costs one line, not a broken call.
set -uo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null) || exit 0
[[ "$tool" == "Bash" ]] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)
[[ -n "$cmd" ]] || exit 0

# already the right door
grep -q "menard" <<<"$cmd" && exit 0

# menard has to be reachable, or this is a repo it does not belong to
root="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -x "$root/modules/menard/bin/menard" ]] || command -v menard >/dev/null 2>&1 || exit 0

grep -qE '(^|[[:space:];&|])mix[[:space:]]+(test|compile|format)([[:space:]]|$)' <<<"$cmd" || exit 0

verb=$(grep -oE 'mix[[:space:]]+(test|compile|format)' <<<"$cmd" | head -1 | awk '{print $2}')
case "$verb" in
  test | compile) want="run $verb" ;;
  format) want="run format" ;;
esac

cat >&2 <<MSG
menard: \`$verb\` has a structured door — \`menard $want [--in DIR]\` returns one line
({"ok":…,"tests":…,"failures":[…]}) with each failure carrying its source, instead of output to
grep. \`menard run check\` is format + warnings-as-errors + tests in one call.
Exception: while editing menard ITSELF, plain mix is right — \`menard run\` would run the
half-edited code.
MSG
exit 2
