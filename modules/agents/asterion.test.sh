#!/usr/bin/env bash
# asterion.sh reaches the right mise task for each way it is called, and passes the rest through
here="$(cd "$(dirname "$0")" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/repo"
printf '#!/bin/sh\necho "$@" >"%s/mise.args"\n' "$work" >"$work/bin/mise"
printf '#!/bin/sh\ntouch "%s/seeded"\n' "$work" >"$work/seed"
chmod +x "$work/bin/mise" "$work/seed"
export PATH="$work/bin:$PATH" ASTERION_SEED="$work/seed" ASTERION_REPO="$work/repo"
bad=0
check() {
	if "$@"; then echo "ok    $*"; else
		echo "WRONG $*"
		bad=1
	fi
}
reaches() {
	local want=$1
	shift
	rm -f "$work/mise.args" "$work/seeded"
	bash "$here/asterion.sh" "$@"
	check test "$(cat "$work/mise.args")" = "--cd $work/repo run $want"
	check test -e "$work/seeded"
}
reaches "house:app --"
reaches "house:run --" dev
reaches "house:widget --" widget
reaches "house:demo --" demo
reaches "house:run -- --flag x" dev --flag x
reaches "house:app -- extra" extra

ASTERION_REPO="$work/missing" bash "$here/asterion.sh" 2>/dev/null
check test $? -eq 1

grep -q 'exec asterion "\$@"' "$here/default.nix"
check test $? -eq 0
exit $bad
