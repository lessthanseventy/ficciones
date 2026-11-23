#!/usr/bin/env bash
# modules/agents/sandbox-sweep.sh removes stale sandbox placeholders and nothing else
sweep="$(cd "$(dirname "$0")" && pwd)/sandbox-sweep.sh"
t=$(mktemp -d)
trap 'chmod -R u+w "$t"; rm -rf "$t"' EXIT
r="$t/repo"
mkdir -p "$r/.claude" "$r/sub/.claude" "$r/node_modules"
git -C "$r" init -q
placeholder() { mkdir -p "$(dirname "$1")" && : >"$1" && touch -d '-5 min' "$1" && chmod 444 "$1"; }

for f in .git/config.lock .mcp.json .bashrc .idea .claude/hooks .claude/settings.json sub/.claude/skills; do
	placeholder "$r/$f"
done
placeholder "$r/.gitmodules"
git -C "$r" add -f .gitmodules
placeholder "$r/live/.mcp.json"
placeholder "$r/node_modules/.mcp.json"
placeholder "$r/notes"
placeholder "$r/.claude/agents/x.md"
: >"$r/.zshrc" && touch -d '-5 min' "$r/.zshrc"
echo real >"$r/.profile" && touch -d '-5 min' "$r/.profile" && chmod 444 "$r/.profile"
: >"$r/.vscode" && chmod 444 "$r/.vscode"

printf '1 0 0:1 / %s rw - x x rw\n' "$r/live/.mcp.json" >"$t/mountinfo"
SANDBOX_SWEEP_MOUNTINFO="$t/mountinfo" bash "$sweep" "$r" >/dev/null

bad=0
expect() {
	local want=$1 f=$2 got=gone
	[ -e "$r/$f" ] && got=kept
	if [ "$got" = "$want" ]; then echo "ok    $want $f"; else
		echo "WRONG $f: $got, want $want"
		bad=1
	fi
}
for f in .git/config.lock .mcp.json .bashrc .idea .claude/hooks .claude/settings.json sub/.claude/skills; do
	expect gone "$f"
done
expect kept .gitmodules
expect kept live/.mcp.json
expect kept node_modules/.mcp.json
expect kept notes
expect kept .claude/agents/x.md
expect kept .zshrc
expect kept .profile
expect kept .vscode
exit $bad
