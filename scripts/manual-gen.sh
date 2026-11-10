#!/usr/bin/env bash
# Write the generated manual pages (docs/manual/{keys,tasks,palette}.md) from their sources, and
# the keys again as the shell's cheatsheet data (modules/desktop/shell/assets/keys.json).
# `--check` only diffs, exit 1 on drift — `mise run manual:check`. Same rule as theme-gen.sh:
# a page with a source is never edited by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-write}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# ---- keys.md: the bind(...) lines of hyprland.lua --------------------------------------------
# hyprctl binds -j only knows a Lua bind as `__lua <n>`, so the SOURCE is the record. Best-effort
# parse: the first argument is the keys (M = SUPER), the second the action. The human line is a
# trailing `--` comment when the bind has one, else the action's entry in WORDS below, else the
# action itself as code.
python3 - modules/desktop/hypr/hyprland.lua "$out/keys.json" >"$out/keys.md" <<'PY'
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read().splitlines()
mod = re.search(r'^local M = "(\w+)"', "\n".join(src), re.M)
M = mod.group(1) if mod else "SUPER"
DIR = {"l": "left", "r": "right", "u": "up", "d": "down"}
WS = {"r+1": "next workspace", "r-1": "previous workspace", "previous": "the workspace you came from", "i": "workspace 1–10"}
WORDS = {
    # the shell's verbs (astal-shell … and shell-req.sh …)
    "toggle launcher": "launcher", "toggle clipboard": "clipboard history", "toggle cheatsheet": "this sheet",
    "toggle drawer": "calendar drawer", "toggle hub": "notifications", "toggle deck": "deck: log · media · agents · timer",
    "toggle dashboard": "dashboard", "toggle settings": "settings", "toggle weather": "weather",
    "show drawer agents": "agents", "show drawer calendar": "calendar", "backdrop": "backdrop: next mode",
    "theme": "light / dark", "crt": "crt scanlines", "glass": "glass", "sidecar toggle": "pin as sidecar",
    "colresize narrower": "column narrower", "colresize wider": "column wider", "quake": "drop-down terminal",
    "focus l": "focus left", "focus r": "focus right", "display send": "window to the other screen",
    "capture shot monitor": "screenshot: monitor", "capture shot window": "screenshot: window",
    "capture shot region": "screenshot: region", "capture rec monitor": "record the monitor", "capture stop": "stop recording",
    "shell/shot-region.sh": "screenshot: region", "shell/shot-region.sh repeat": "screenshot: the same region again",
    # commands
    "ghostty": "terminal", "dolphin": "files", "floorp": "browser", "kate": "editor", "pavucontrol": "audio mixer",
    "ghostty -e btop": "btop", "hyprpicker -a": "colour picker", "loginctl lock-session": "lock",
    "systemctl poweroff": "power off", "playerctl play-pause": "play / pause", "playerctl next": "next track",
    "playerctl previous": "previous track", "brightnessctl set 5%+": "brightness up", "brightnessctl set 5%-": "brightness down",
    "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+": "volume up", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-": "volume down",
    "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle": "mute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle": "mute the microphone",
    # the layout and the compositor
    'layout("focus u")': "focus up in the column", 'layout("focus d")': "focus down in the column",
    'layout("move -col")': "scroll one column left", 'layout("move +col")': "scroll one column right",
    'layout("swapcol l")': "swap column left", 'layout("swapcol r")': "swap column right",
    'layout("fit active")': "fit the active column", 'layout("fit expand")': "fit: expand", 'layout("fit all")': "fit all columns",
    'layout("fit visible")': "fit the visible columns", 'layout("fit_into_view")': "bring the column into view",
    'layout("center")': "centre the column", 'layout("consume")': "pull the next window into the column",
    'layout("promote")': "window into its own column",
    'layout("consume_or_expel prev")': "stack / unstack toward the left", 'layout("consume_or_expel next")': "stack / unstack toward the right",
    'layout("colresize +conf")': "column: next preset width", 'layout("colresize -conf")': "column: previous preset width",
    "resize(0, -100)": "window shorter", "resize(0, 100)": "window taller",
    'hl.dsp.focus({ monitor = "l" })': "focus the left monitor", 'hl.dsp.focus({ monitor = "r" })': "focus the right monitor",
    "hl.dsp.focus({ last = true })": "the window you came from", "hl.dsp.window.close()": "close", "hl.dsp.window.kill()": "kill",
    "hl.dsp.window.float()": "float / tile", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })': "fullscreen",
    "hl.dsp.window.fullscreen_state({ internal = 0, client = 3 })": "tell the app it is fullscreen, keep it tiled",
    "hl.dsp.window.drag()": "drag the window", "hl.dsp.window.resize()": "resize the window", "hl.dsp.exit()": "leave Hyprland",
    'hl.dsp.dpms({ action = "off" })': "screens off", 'function() hl.plugin.hyprexpo.expo("toggle") end': "overview",
}
def words(a):
    """The action in words, or None."""
    m = re.match(r'(move|move_mon|ws|to_ws|follow_ws)\("?([^")]+)"?\)$', a)
    if m:
        f, x = m.groups()
        if f == "move": return f"move window {DIR[x]}"
        if f == "move_mon": return f"column to the {DIR[x]} monitor"
        return {"ws": "", "to_ws": "window to ", "follow_ws": "follow the window to "}[f] + WS[x]
    e = re.match(r'exec\((.*)\)$', a)
    if not e: return WORDS.get(a)
    cmd = re.sub(r'^shell \.\. "/', "shell/", e.group(1).strip()).strip('"')
    return WORDS.get(re.sub(r"^(astal-shell|shell/shell-req\.sh) ", "", cmd))
rows = []
for line in src:
    m = re.match(r'^\s*bind\((.*)\)\s*(?:--\s*(.*))?$', line)
    if not m: continue
    inner, comment = m.group(1), (m.group(2) or "").strip()
    # keys = everything up to the first top-level comma
    depth, cut = 0, None
    for i, ch in enumerate(inner):
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        elif ch == "," and depth == 0: cut = i; break
    if cut is None: continue
    keys_expr, action = inner[:cut], inner[cut+1:].strip()
    keys = "".join(M if p.strip() == "M" else p.strip().strip('"') for p in keys_expr.split(".."))
    keys = re.sub(r"\s*\+\s*", "+", keys)
    mouse = "mouse = true" in action
    action = re.sub(r",\s*\{[^{}]*\}\s*$", "", action).strip()
    def group(a):
        if a.startswith(("move(", "move_mon(", "resize(")) or "colresize" in a or "sidecar" in a or "display send" in a: return "move & size"
        if "shell-req.sh focus" in a: return "focus"
        if "capture " in a or "shot-region" in a or "hyprpicker" in a or "grim " in a: return "capture"
        if re.search(r"wpctl|playerctl|brightnessctl", a): return "media"
        if "astal-shell" in a or "shell-req.sh" in a: return "shell"
        if a.startswith("exec("): return "launch"
        if a.startswith(("ws(", "to_ws(", "follow_ws(")): return "workspaces"
        if a.startswith("layout("): return "layout"
        if a.startswith("hl.dsp.focus"): return "focus"
        if a.startswith("hl.dsp.window") or a.startswith("unless_pinned("): return "window"
        return "other"
    def what(a, c):
        if c: return c
        if words(a): return words(a)
        e = re.match(r'exec\((.*)\)$', a)
        if e:
            arg = e.group(1).strip().strip('"')
            arg = re.sub(r'^shell \.\. "/', "shell/", arg).strip('"')
            return "`" + arg[:60] + "`"
        return "`" + a[:60] + "`"
    rows.append(("mouse" if mouse else group(action), keys, what(action, comment)))
order = ["launch", "shell", "focus", "move & size", "layout", "workspaces", "window", "capture", "media", "mouse", "other"]
# the same rows for the shell's cheatsheet: one parse, two readers
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump([{"group": g, "keys": k, "does": w.strip("`")} for g in order for (rg, k, w) in rows if rg == g], f, ensure_ascii=False, indent=1)
    f.write("\n")
print("# Keys\n")
print("Generated from `modules/desktop/hypr/hyprland.lua` by `mise run manual:gen` — edit THAT, never this file.")
print(f"{len(rows)} binds. `{M}` is the main modifier. The shell draws the live sheet too (`astal-shell toggle cheatsheet`, bound under launch).\n")
for g in order:
    mine = [r for r in rows if r[0] == g]
    if not mine: continue
    print(f"## {g}\n\n| keys | does |\n|---|---|")
    for _, k, w in mine: print(f"| `{k}` | {w} |")
    print()
PY

# ---- tasks.md: every mise verb, by group -------------------------------------------------------
# only this repo's: mise merges every mise.toml up the tree, and the page must not vary by machine
mise tasks ls --json | jq --arg root "$PWD/" '[.[] | select(.source | startswith($root))]' >"$out/tasks.json"
python3 - "$out/tasks.json" >"$out/tasks.md" <<'PY'
import json, sys
tasks = json.load(open(sys.argv[1]))
groups = {}
for t in tasks:
    g = t["name"].split(":")[0] if ":" in t["name"] else "—"
    groups.setdefault(g, []).append(t)
print("# Verbs\n")
print("Every verb is `mise run <name>`; the same loop for the human and the agents (AGENTS.md). Generated by `mise run manual:gen` from `mise tasks ls --json` — a verb is defined in `tasks/<group>.toml`, never here.\n")
print(f"{len(tasks)} verbs in {len(groups)} groups. The launcher lists them under `>`.\n")
for g in sorted(groups):
    print(f"## {g}\n\n| verb | does |\n|---|---|")
    for t in sorted(groups[g], key=lambda t: t["name"]):
        d = (t.get("description") or "").replace("|", "\\|").replace("\n", " ")
        print(f"| `{t['name']}` | {d} |")
    print()
PY

# ---- palette.md: the roles, every palette --------------------------------------------------------
roles="$(nix eval --json --impure --expr '
  let ps = import ./modules/desktop/theme/palettes;
  in { roles = builtins.mapAttrs (_: p: p.role) ps; font = ps.uqbar.font; }')"
python3 - "$roles" >"$out/palette.md" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
print("# Palette\n")
print("Generated by `mise run manual:gen` from `modules/desktop/theme/palettes/` (one file per palette, listed in `default.nix`) — the palette is data there; every surface (shell, office, ghostty, GTK/Qt, btop, floorp, hyprlock, lazygit, bat, fzf, cava, tmux, Claude Code, Neovim) is rendered from it by `render.nix`. Nothing else on the machine carries a hex value.\n")
print(f"Font: **{p['font']['family']}** everywhere, {p['font']['size']}pt base (low vision: sizes bias up, never down).\n")
print("## The law\n")
print("- **Body text is amber on black** (uqbar) — dark amber on cream in zahir. The paper pair: graphite on notebook paper (babel), chalk on charcoal (hronir); Super+Shift+P flips within a pair. Cyan = keys, labels, code, links. Lilac = secondary text.")
print("- **Amber field = the CURSOR** (where you are: focused workspace, active tab, list row) as inverse video. **Violet field = the SELECTION** (what you picked and left behind). The test: *if you look away, does it stay?*")
print("- Green = live/occupied. Pink = agents, the operator, attention. Red = alarm. Ember = warning, one step before red.")
print("- Every pair clears WCAG AAA (7:1 text, 3:1 bands) in EVERY palette — `mise run theme:contrast` proves it.\n")
print("- **A wallpaper per palette:** `wallpapers = [ \"~/Pictures/Wallpapers/uqbar\" ];` in `palettes/<name>.nix` (files or directories) makes the shell's photo backdrop draw from them while that palette is live; empty falls back to the shared wallpapers directory. `mise run home:switch` to apply.\n")
names = sorted(p["roles"])
print("## Roles\n\n| role | " + " | ".join(names) + " |\n|---|" + "---|" * len(names))
for k in sorted(p["roles"]["uqbar"]):
    print(f"| `{k}` | " + " | ".join(f"`#{p['roles'][n].get(k, '—')}`" for n in names) + " |")
print()
print("Surfaces name a ROLE, never a hue — `render.nix` cannot reach `p.hue`. Syntax colouring in Neovim is a CATEGORY tier (base16 slots bound in `render.nix`), the one place hues are bound for code.")
PY

rc=0
for f in keys.md tasks.md palette.md keys.json; do
	dst="docs/manual/$f"
	[ "$f" = keys.json ] && dst="modules/desktop/shell/assets/keys.json"
	if [ "$mode" = "--check" ]; then
		if ! diff -u "$dst" "$out/$f" >/dev/null 2>&1; then
			echo "manual:check — $dst drifts from its source (run: mise run manual:gen)"
			rc=1
		fi
	else
		cp "$out/$f" "$dst"
		echo "manual:gen — wrote $dst"
	fi
done
exit $rc
