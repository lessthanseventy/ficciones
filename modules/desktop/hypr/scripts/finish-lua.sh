#!/usr/bin/env bash
# The last step of the hyprland.conf → hyprland.lua port (2026-09-05): once a Hyprland has
# STARTED on the .lua, drop the .conf twins. Refuses while the running instance is still on
# the .conf — ~/.config/hypr/hyprland.conf is an out-of-store link into this tree, and a
# running Hyprland reloads to its built-in defaults the moment that link dangles.
#
#   mise run hypr:finish-lua        (after a log out / log in, or a Hyprland restart)
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sig="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$rt/hypr" 2>/dev/null | head -1)}"
log="$rt/hypr/$sig/hyprland.log"
if [ ! -f "$log" ] || ! grep -q "Using lua config" "$log"; then
  echo "hypr:finish-lua — the running Hyprland did not start on hyprland.lua (no 'Using lua config' in $log)." >&2
  echo "hypr:finish-lua — log out and back in (a reload is not enough: the config PATH is fixed at start), then run this again." >&2
  exit 1
fi
echo "hypr:finish-lua — Hyprland $sig is on the .lua; removing the .conf transition"

git rm -q modules/desktop/hypr/hyprland.conf modules/desktop/hypr/hosts/*.conf

python3 - <<'EOF'
import re
p='modules/desktop/default.nix'; s=open(p).read()
old='''      # TRANSITION (2026-09-05): a running Hyprland stays pinned to the config path it started
      # with, so the .conf (and its host/theme includes) stay linked until the next Hyprland
      # start picks hyprland.lua. Delete these three lines + hyprland.conf + hosts/*.conf then.
      "hypr/hyprland.conf" = linkTo "hyprland.conf";
      "hypr/host.conf" = linkTo "hosts/${cfg.host}.conf";
'''
assert old in s, 'default.nix transition block not found'
s=s.replace(old,'')
s=s.replace('''    # hyprland.conf goes down home-manager's slow path''','''    # hyprland.lua goes down home-manager's slow path''')
open(p,'w').write(s)

p='modules/desktop/theme/default.nix'; s=open(p).read()
old=re.search(r'  envConf =\n(?:    .*\n)+?  envLua =', s)
assert old, 'envConf not found'
s=s.replace(old.group(0),'  envLua =')
for line in ['    "hypr-theme.conf" = r.hyprlandTheme + envConf;\n',
             '        "hypr/theme.conf" = via "hypr-theme.conf"; # TRANSITION, see modules/desktop/default.nix\n']:
    assert line in s, line
    s=s.replace(line,'')
open(p,'w').write(s)

p='modules/desktop/theme/render.nix'; s=open(p).read()
m=re.search(r"  # Sourced by hyprland\.conf \(and required by hyprland\.lua\): only the colours live here\.\n  hyprlandTheme = ''\n.*?\n  '';\n\n", s, re.S)
assert m, 'hyprlandTheme block not found'
s=s.replace(m.group(0),'')
open(p,'w').write(s)
EOF

# the machine gate (evaluates the trimmed modules), then the live instance must still be clean
mise run home:switch
errs=$(hyprctl configerrors 2>/dev/null | grep -v "^$" || true)
[ -z "$errs" ] || { echo "hypr:finish-lua — hyprctl configerrors is not empty after the switch:" >&2; echo "$errs" >&2; exit 1; }
git add -A modules/desktop
git commit -q -F - <<'EOF'
chore(hypr): the .conf transition is over — hyprland.conf, hosts/*.conf, theme.conf and their links are gone; hyprland.lua is the config

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
echo "hypr:finish-lua — done: $(git log --oneline -1)"
