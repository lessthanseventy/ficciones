#!/usr/bin/env bash
# Claude Code's statusline: claude-powerline's 2-line minimal render in a compact box, coloured
# from the LIVE theme (~/.config/ficciones/theme/palette.sh — a theme switch changes the next
# repaint), plus the background agents Claude's default statusline shows: Agent calls and
# background Bash tasks in this session's transcript with no task-notification yet.
# - line 2 (usage) is recoloured fg-only, live→chip→red by each segment's percentage
# - labels are sed'd in after claude-powerline's fixed segment icons (it has no label option)

CPL=/home/andrew/.local/share/mise/shims/claude-powerline
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/ficciones/theme"
[ -r "$THEME/palette.sh" ] && . "$THEME/palette.sh"
rgb() { local h="${1#\#}"; printf '\033[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
BORDER=$(rgb "${PALETTE_AMBER:-FFB000}")
LIVE=$(rgb "${PALETTE_GREEN:-33FF00}"); WARM=$(rgb "${PALETTE_CHIP:-FFD000}"); HOT=$(rgb "${PALETTE_RED:-FF5555}"); PINK=$(rgb "${PALETTE_PINK:-E0218A}")
RESET=$'\033[0m'

input=$(cat)
raw=$(printf '%s' "$input" | "$CPL" 2>/dev/null \
  | sed -e 's/◔/󰧑  ctx/g' -e 's/◱/⏱  5h/g' -e 's/◑/▦  wk/g')
mapfile -t L <<< "$raw"

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
  L[1]=$(printf '%s' "${L[1]}" \
    | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
    | awk -v live="$LIVE" -v warm="$WARM" -v hot="$HOT" '
        function pick(p) { if (p+0 >= 80) return hot; else if (p+0 >= 50) return warm; else return live }
        {
          gsub(/󰧑/, "\001󰧑"); gsub(/⏱/, "\001⏱"); gsub(/▦/, "\001▦");
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
