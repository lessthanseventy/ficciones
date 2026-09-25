#!/usr/bin/env bash
# The names-exist gate: every name the glue points at must exist in what it points at. Nothing
# compiles these seams, so a rename fails silently at 2am — this catches it at commit time.
#
#   (c) `mise run <task>` in any AGENTS.md / README.md, mise.toml, scripts, flake.nix
#       →  a task `mise tasks ls` knows (`<prefix>:*` is a glob: some task must match)
#   (d) a ~/.pi/agent/<file>.json tlon's adapters read  →  one flake.nix writes
#       (`home.file.".pi/agent/<file>"`, or a seeded `"$HOME/.pi/agent/<file>"`)
#
# grep only, offline, a few hundred ms. One line per miss; exit 1 if any. docs/ is not an
# input: prose there may name a retired task on purpose.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
tlon="${TLON_REPO:-$HOME/projects/tlon}"

fail=0
miss() { echo "check-names: $*"; fail=1; }

# This file names the patterns it hunts; every other script is an input.
scripts="$(ls scripts/*.sh | grep -v '/check-names.sh$')"
guides() { find . -path '*/node_modules' -prune -o -path ./.worktrees -prune -o -path ./.git -prune -o -path ./docs -prune -o \( -name AGENTS.md -o -name README.md \) -print; }

# ---- (c) mise tasks ---------------------------------------------------------------------------
# Only tasks THIS repo defines: mise merges every mise.toml up the directory tree, so a parent's
# tasks would otherwise mask a miss.
known="$(mise tasks ls --json 2>/dev/null | jq -r --arg root "$root/" '.[] | select(.source | startswith($root)) | .name' | sort -u)"
[ -n "$known" ] || miss "(c) \`mise tasks ls\` lists no task from $root — is mise on PATH and are the task files parseable?"
n_mise=0
while IFS=: read -r file line ref; do
  [ -n "$ref" ] || continue
  n_mise=$((n_mise + 1))
  task="${ref#mise run }"
  task="${task%:}"            # a sentence-final "home:switch:" is the task, not a namespace
  case "$task" in
    *\*) grep -q "^${task%\*}" <<<"$known" || miss "(c) $file:$line names \`$ref\` — no task matches that prefix in \`mise tasks ls\`" ;;
    *) grep -qxF "$task" <<<"$known" || miss "(c) $file:$line names \`$ref\` — not a task \`mise tasks ls\` knows" ;;
  esac
done < <(grep -noE 'mise run [A-Za-z0-9:_*-]+' mise.toml flake.nix $scripts $(guides) 2>/dev/null | sort -u)

# ---- (d) pi config files tlon's adapters read -------------------------------------------------
n_pi=0
if [ -d "$tlon/adapters" ]; then
  while IFS=: read -r file line path; do
    [ -n "$path" ] || continue
    n_pi=$((n_pi + 1))
    rel="${path#*.pi/agent/}"
    grep -qF "home.file.\".pi/agent/$rel\"" flake.nix || grep -qF "\"\$HOME/.pi/agent/$rel\"" flake.nix ||
      miss "(d) $file:$line reads ~/.pi/agent/$rel — flake.nix writes no such file (home.file / seed)"
  done < <(find "$tlon/adapters" -path '*/node_modules' -prune -o -type f -name '*.ts' -print | xargs grep -noE '\.pi/agent/[A-Za-z0-9_./-]+\.json' 2>/dev/null | sort -u)
else
  miss "(d) no tlon checkout at $tlon — set TLON_REPO"
fi

if [ "$fail" -ne 0 ]; then
  echo "check-names: FAILED — a name above points at nothing (rename left a dangling reference)"
  exit 1
fi
echo "check-names: ok — $n_mise mise-task refs, $n_pi pi config files all resolve"
