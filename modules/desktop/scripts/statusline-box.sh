#!/usr/bin/env bash
# Claude Code's statusline: claude-powerline's 2-line minimal render in a compact box, coloured
# from the LIVE theme (~/.config/ficciones/theme/palette.sh — a theme switch changes the next
# repaint), plus the background agents Claude's default statusline shows: Agent calls and
# background Bash tasks in this session's transcript with no task-notification yet.
# - line 2 (usage) is recoloured fg-only, live→chip→red by each segment's percentage
# - labels are sed'd in after claude-powerline's fixed segment icons (it has no label option)

CPL=${CLAUDE_POWERLINE:-/home/andrew/.local/share/mise/shims/claude-powerline}
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/ficciones/theme"
[ -r "$THEME/palette.sh" ] && . "$THEME/palette.sh"
rgb() {
	local h="${1#\#}"
	printf '\033[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
BORDER=$(rgb "${PALETTE_AMBER:-FFB000}")
LIVE=$(rgb "${PALETTE_GREEN:-33FF00}")
WARM=$(rgb "${PALETTE_CHIP:-FFD000}")
HOT=$(rgb "${PALETTE_RED:-FF5555}")
PINK=$(rgb "${PALETTE_PINK:-E0218A}")
RESET=$'\033[0m'

input=$(cat)
# in a linked worktree the folder shown is the main checkout's: which worktree it is belongs to
# the changes pane
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
if [ -n "$dir" ] && top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
	common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
	if [ "${common##*/}" = .git ] && [ "$common" != "$top/.git" ]; then
		input=$(printf '%s' "$input" | jq -c --arg d "${common%/.git}${dir#"$top"}" '.workspace.current_dir = $d | .cwd = $d')
	fi
fi
raw=$(printf '%s' "$input" | "$CPL" 2>/dev/null |
	sed -e 's/◔/󰧑  ctx/g' -e 's/◱/⏱  5h/g' -e 's/◑/▦  wk/g')
mapfile -t L <<<"$raw"

# ctx: trust Claude Code's own used_percentage (its compaction popup keys off this); claude-powerline
# recomputes from raw token counts and under-reads badly (60% shown at the ~90% popup)
# the context window's own field — the JSON carries three used_percentage keys (context,
# 5h limit, 7d limit) and a greedy sed took the last: ctx showed the weekly number
# and it is a share of the model's whole window: with `autoCompactWindow` (433k of a 1M window) the
# compaction comes at 40%, so ctx is the context's tokens over that budget when it is set.
# Claude Code compacts 33k short of the window (20k kept for the summary, 13k of margin), and its
# "N% until auto-compact" counts to there: so does this, or the two disagree by 8% at the end
cap=$(jq -r '(.autoCompactWindow // null) | if type == "number" then . - 33000 else . end' "$HOME/.claude/settings.json" 2>/dev/null)
used=$(printf '%s' "$input" | jq -r --argjson cap "${cap:-null}" '
  .context_window as $c | ($c.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $t
  | if ($cap | type) == "number" and $t > 0 then $t * 100 / $cap else ($c.used_percentage // empty) end' 2>/dev/null)
if [ -n "$used" ] && [ "${#L[@]}" -ge 2 ]; then
	used=$(printf '%.0f' "$used")
	L[1]=$(printf '%s' "${L[1]}" | sed -E "s/(ctx[^%]*[^0-9])[0-9]+%/\1${used}%/")
fi

# the session's meter beside its record (modules/agents/session-state.sh), for the desktop's rows:
# a file of its own so the hook and the repaint never write over each other, written only on a change
id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
meters="${XDG_RUNTIME_DIR:-/tmp}/sessions"
if [ -n "$used" ] && [ -d "$meters" ] && [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]]; then
	meter=$(printf '%s' "$input" | jq -c --argjson ctx "$(printf '%.0f' "$used")" '{ctx: $ctx, model: (.model.display_name // null)}' 2>/dev/null)
	if [ -n "$meter" ] && [ "$meter" != "$(cat "$meters/$id.meter" 2>/dev/null)" ]; then
		printf '%s\n' "$meter" >"$meters/.$id.meter" && mv -f "$meters/.$id.meter" "$meters/$id.meter"
	fi
fi

# a model family's own weekly limit (Fable's, beside the all-models one) is not in the input:
# it is read from the account's usage endpoint, at most every five minutes and behind the
# repaint; the touch is what keeps a failing read from being tried on every repaint
usage="${XDG_RUNTIME_DIR:-/tmp}/claude-usage.json"
if [ -z "$(find "$usage" -mmin -5 2>/dev/null)" ]; then
	touch "$usage"
	(
		tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
		[ -n "$tok" ] && curl -sf -m 5 https://api.anthropic.com/api/oauth/usage \
			-H "Authorization: Bearer $tok" -H 'anthropic-beta: oauth-2025-04-20' -o "$usage.new" &&
			mv -f "$usage.new" "$usage"
	) </dev/null >/dev/null 2>&1 &
fi
scoped=$(jq -r '[.limits[]? | select(.kind == "weekly_scoped")][0] | select(.)
  | "\(.scope.model.display_name | ascii_downcase) \(.percent)%"' "$usage" 2>/dev/null)
if [ -n "$scoped" ] && [ "${#L[@]}" -ge 2 ]; then
	L[1]="${L[1]}  ✦  ${scoped}"
fi

effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
if [ -n "$effort" ] && [ "${#L[@]}" -ge 1 ]; then
	L[0]="${L[0]} ${WARM}◆ ${effort}${RESET}"
fi

# background agents: unanswered Agent / background-Bash tool uses in the transcript
transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path":"\([^"]*\)".*/\1/p')
agents=0
if [ -r "$transcript" ]; then
	agents=$(tail -n 400 "$transcript" | python3 -c '
import sys, json, re
started, done = {}, set()
for line in sys.stdin:
    try: j = json.loads(line)
    except Exception: continue
    m = j.get("message") or {}
    c = m.get("content")
    if isinstance(c, list):
        for b in c:
            if not isinstance(b, dict): continue
            if b.get("type") == "tool_use":
                n, i = b.get("name"), b.get("input") or {}
                if n == "Agent" or (n == "Bash" and i.get("run_in_background")) or n == "Monitor":
                    started[b.get("id")] = n
            if b.get("type") == "text":
                for tid in re.findall(r"<tool-use-id>([^<]+)</tool-use-id>", b.get("text", "")): done.add(tid)
    elif isinstance(c, str):
        for tid in re.findall(r"<tool-use-id>([^<]+)</tool-use-id>", c): done.add(tid)
print(sum(1 for i in started if i not in done))
' 2>/dev/null || echo 0)
fi
if [ "${agents:-0}" -gt 0 ] && [ "${#L[@]}" -ge 1 ]; then
	L[0]="${L[0]} ${PINK}⚑ ${agents} agent$([ "$agents" -ne 1 ] && echo s)${RESET}"
fi

if [ "${#L[@]}" -ge 2 ]; then
	L[1]=$(printf '%s' "${L[1]}" |
		sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' |
		awk -v live="$LIVE" -v warm="$WARM" -v hot="$HOT" '
        function pick(p) { if (p+0 >= 80) return hot; else if (p+0 >= 50) return warm; else return live }
        {
          gsub(/󰧑/, "\001󰧑"); gsub(/⏱/, "\001⏱"); gsub(/▦/, "\001▦"); gsub(/✦/, "\001✦");
          n = split($0, seg, "\001");
          out = seg[1];
          for (i = 2; i <= n; i++) {
            pct = 0;
            if (match(seg[i], /[0-9]+%/)) pct = substr(seg[i], RSTART, RLENGTH - 1) + 0;
            out = out pick(pct) seg[i] "\033[0m";
          }
          printf "%s", out;
        }')
fi

printf '%s\n' "${L[@]}" | awk -v b="$BORDER" -v r="$RESET" '
  function vislen(s,   t) { t = s; gsub(/\033\[[0-9;?]*[a-zA-Z]/, "", t); return length(t) }
  { lines[NR] = $0; w = vislen($0); if (w > max) max = w }
  END {
    bar = ""; for (i = 0; i < max + 2; i++) bar = bar "─"
    print b "╭" bar "╮" r
    for (n = 1; n <= NR; n++) {
      pad = max - vislen(lines[n])
      sp = ""; for (i = 0; i < pad; i++) sp = sp " "
      print b "│" r " " lines[n] sp " " b "│" r
    }
    print b "╰" bar "╯" r
  }'
