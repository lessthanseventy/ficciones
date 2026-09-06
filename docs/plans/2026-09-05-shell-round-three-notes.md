# Shell round three — running notes (2026-09-05)

Andrew asked for ALL of these in one go; low on his 5h chunk, reset in <1h, so this file is the
resume point. Branch `astal-shell`. Each item lands as its own small commit. Update the status
column as work lands.

## The list

| # | item | status | notes |
|---|------|--------|-------|
| D1 | per-core sparklines + killable process list (click-to-kill, cpu/mem sort toggle) | done | perf.ts coreHist (40s), panes/Perf.tsx Procs+CoreGrid |
| D2 | DISK card (df per mount as meters) + NET card (wifi signal history, SSID, IP) | done | lib/disk.ts lib/wifi.ts panes/Disk.tsx panes/Net.tsx |
| D3 | TODAY card: missed notifications + khal agenda + agents awaiting, one "needs me" list | done | panes/Today.tsx; agenda exported from Calendar |
| D4 | JOURNAL card: last few journalctl lines at warning+ | done | lib/journal.ts panes/Journal.tsx (6 lines, sys+user) |
| D5 | WORKSPACES overview card: every ws with window icons, click to jump | done | panes/Workspaces.tsx; WindowStrip reusable for S3; lib/icons.ts |
| S1 | sidecar width by drag (grab handle on the zone's right edge) | done, UNTESTED live (would have unpinned Andrew's window mid-use) | lib/sidecar.ts makeHandle/resize; drag reads Hyprland cursorpos, not widget offsets |
| S2 | OSD for volume/brightness — Andrew (mid-session): WANTED, and MORE prominent than a thin meter (headphone buttons change volume unseen); scroll on the rail's volume icon changes volume; a slider move in the popover SKIPS the OSD | done | surfaces/Osd.tsx; quietOsd() from Audio slider/mute + Backlight; Tray Vol scroll caps at 100% |
| S3 | hover-open on rail workspace numbers → strip of that ws's windows | done | Rail ws → menubutton + WorkspacePop (panes/Workspaces.tsx); hover untested live (movecursor moves his mouse) |
| S4 | notification actions inline on toasts | done | actions already rendered; now outlined green buttons; verified with notify-send -A |
| S5 | (mid-session ask) battery cell click-to-open + wheel = brightness/gamma | done | lib/brightness.ts; OSD hooks gamma via onGammaChange |
| P1 | "paper" light palette variant; `astal-shell theme paper` reruns home:switch in bg | done (paper values UNSEEN live — switching reruns home:switch for minutes; Andrew to try `astal-shell theme paper`) | theme/palette.nix selector + current + palettes/{amber,paper}.nix; shell lib/theme.ts |
| P2 | floorp userContent rules for lived-in sites from the palette | done — SITE LIST IS MY GUESS (github, claude.ai, HN, reddit, wikipedia, google, youtube); Andrew to prune/extend theme/floorp-sites.nix; lands on next home:switch | |
| S6 | (mid-session ask) workspace hover strip = real window thumbnails, only after a LONG hover | done | lib/thumbs.ts (jpeg, ~/.cache/astal-shell/thumbs), hoverPopover dwell 900ms; strip unseen live (needs a real hover) |
| S7 | (mid-session ask) popover arrow+gap universal: clock/calendar + weather as rail popovers | done | Drawer.tsx + WeatherPop.tsx DELETED; drawer j/k nav gone with them (was vestigial); keybinds pop on the focused monitor's rail; palette-sync check green |
| B1 | Library of Babel zen mode: hexagonal cells of drifting amber text, real book fragments | done, seen live | lib/babel.ts; Mode.text() path in ambient/Backdrop; books in ~/.cache/astal-shell/babel; whole hex columns only (Andrew: edges were cut) |
| B2 | Funes launcher: frecency ranking of everything typed | done | lib/funes.ts; Launcher recall()/remember(); history empty until used |

## Gates
- `mise shell:check` after each batch (ags bundle is the hard gate).
- `mise theme:gen` + `nix flake check` when the palette/render change (P1, P2).
- Live: `mise shell:dev` (pkill gjs first); screenshot with `grim -o eDP-1`.

## Decisions / gotchas discovered
- Board layout is 3 rows packed for 1920×1080 (DP-2): [NOW/WORKSPACES | WEATHER | CALENDAR/TODAY | POWER/SHELL], [PERF | AGENTS/MEDIA | DISK/NET], [JOURNAL | TOGGLES]. Andrew OK'd shrinking the board's type a notch (13/11/16) so it all shows — the ONE exception to sizes-bias-up.
- `mise shell:check`'s `ags types` step needs the network (npx) → fails in the sandbox; `ags bundle` alone is the hard gate.
- Sandbox has a PID namespace + blocks the Hyprland socket: live checks (pgrep gjs, hyprctl, grim, ags request) need the sandbox off.
- Live loop used: `pkill -x gjs; nohup ags run app.tsx &` from modules/desktop/shell, then `ags request -i astal-shell toggle dashboard`, `grim -o DP-2`.

## State at the end of the session (2026-09-05 ~22:45)
- Every item above is committed on `astal-shell` (18 commits this round). The LIVE shell is `ags run app.tsx` from the working tree (source build), not the store package — a `home:switch` + "restart shell" puts the store build back in charge.
- Untested by eye: sidecar drag (S1), the workspace thumbnail strip on hover (S6), the paper palette live (P1), the floorp site rules (P2 — lands on home:switch; open github/claude.ai afterwards).
- Not run this round: `mise flake:check` / `home:switch` (the machine gate). palette-sync check IS green. Run flake:check before calling the round done.
- Rail's Drawer/WeatherPop windows are gone; `astal-shell toggle drawer` / `show drawer calendar` now pop the calendar off the clock on the focused monitor.

## 2026-09-06 00:xx — sidecar rework (Andrew: "feel like the first window on the workspace")
- Drag handle dropped. Keybind resize → poll `j/clients` every 500ms → zone follows, window re-placed on the left edge.
- Mark = `dispatch setprop <addr> border_size 3 / active_border_color rgb(pink) / inactive_border_color rgb(dim)`; `unset` restores. (setprop is a DISPATCHER in 0.56; plain `hyprctl setprop` → "unknown request".)
- Zone: Astal `exclusivity: EXCLUSIVE` reads back 0 inside the shell (works in a bare ags app — unexplained); `Gtk4LayerShell.set_exclusive_zone(w, col)` explicit works. Layer TOP so it is arranged after the rail (BOTTOM got the left strip and shoved the rail right).
- Scrolling layout only re-fits on a config change: relayout = `keyword general:gaps_out <same>` + `dispatch layoutmsg "fit visible"`, with a 1.2s settle window on the poll (Hyprland nudges floating windows on relayout → fed back → ballooned to MAX once).
- Verified live on DP-2 with a throwaway ghostty: pin → reserved 714, columns fit beside; resize +200 → reserved 914; unpin → back to 61.

## 2026-09-06 00:xx–01:xx — "make sure everything gets done"
- Keybinds: Ctrl+Super+P = sidecar toggle; Super+;/'/-/= → `astal-shell colresize narrower|wider` (sidecar resizes, else layoutmsg colresize); Super+Shift+P = light/dark (`astal-shell theme`); Super+Shift+Z = backdrop cycle; Super+O = hyprexpo overview (plugin).
- Zen toggle (toggles card) now cycles modes and shows the mode name; a paper/dark toggle sits beside it.
- SIDECAR FINAL SHAPE: no zone window. The RAIL's exclusive zone is widened by the column (lib/railzone.ts, gtk4-layer-shell set_exclusive_zone / auto_exclusive_zone_enable). Bisected in-shell: a content-less Astal.Window reserves fine (excl=1, 500px) UNTIL it is made invisible — `background: transparent` rule, `opacity: 0` (CSS or property), any `window.<class>` rule → surface 200px, zone 0. Opaque works but on BOTTOM it is arranged before the rail. So: rail zone. Verified pin 906 / narrower 810 / wider 906 / unpin 61 through the real `astal-shell` wrapper (~0.35s per call).
- Thumbnail strip: textures pre-scaled to 140px (GdkPixbuf at_scale) so the popover is thumbnail-sized; every showing workspace recaptures every 5s; background workspaces show their last capture. `astal-shell pop ws N` opens a strip for debugging. LIVE previews are impossible from a client → hyprexpo (compositor plugin).
- hyprexpo: flake input `hyprexpo` (sandwichfarm fork); modules/os pins Hyprland to that flake's build and drops the .so at /etc/hypr/plugins/hyprexpo.so; hyprland.lua loads it at start when present. ARCH BOX: needs `hyprpm update && hyprpm add https://github.com/sandwichfarm/hyprexpo && hyprpm enable hyprexpo` BY ANDREW (sudo for headers; hyprpm from here failed on the header install). Until then Super+O does nothing. Andrew vetoed AUR installs mid nix-migration (a hyprexpose AUR build was started and killed; nothing installed).
- Theme: `astal-shell theme paper` had left `current=paper` + generated files; my `git add -A modules/desktop` swept them into a commit; reset to amber. home:switch had failed on a stale empty `.git/config.lock` (22:07) in the hyprlandGitHooks step — removed, switch green, store shell + ghostty theme + floorp sites installed.

## 2026-09-06 01:xx–02:00 — live theme switch, WCAG, Claude Code
- Theme switch is LIVE (<1s): home-manager renders both palettes into ~/.config/ficciones/themes/{uqbar,zahir}; every app path is a link through ~/.config/ficciones/theme; `astal-shell theme` (Super+Shift+P / toggles card) repoints it, applies the shell css + Pango palette in place, hyprctl reload, ghostty SIGUSR2 + OSC recolour of open surfaces (~/.local/bin/ficciones-recolor), gsettings colour-scheme, and `theme: custom:<name>` in ~/.claude/settings.json. The shell package compiles a css per palette (dart-sass). palette.nix `current` = build-time default only.
- Palettes renamed uqbar (dark) / zahir (light). WCAG: every text hue ≥ 7:1 on its ground, borders ≥ 3:1 (lightness moved, hue kept) in BOTH palettes.
- Claude Code: themes per palette at ~/.claude/themes/{uqbar,zahir}.json (rendered), statusline-box.sh + claude-powerline.json in the flake, colours from the live theme, `⚑ N agents` from the transcript. LIMIT: Claude Code loads a custom theme once per session; switching between two custom themes mid-session renders a mix — restart the session after a switch (bug report drafted via SendFeedback).
- hyprexpo INSTALLED on Arch via hyprpm (Andrew ran it; sudo-askpass now handles no-tty), themed from the palette in theme.conf/.lua; Super+O.
- Quake terminal: pinned while shown (over the sidecar), parked on special:quake, no_anim + a scripted slide from the top (QUAKE_STYLE=fade alt; tag quake-fade-checkpoint), 70%×55% below the bar, focus returns on hide.
- Sidecar: outer pink ring (shell layer window) + inner Hyprland border amber/dim; ring hides under another pinned window; Super+H/L stitch focus; binds via scripts/shell-req.sh (D-Bus, 15ms).
- Naming survey was started (inventory: Tlön 147 files, funes 104, cockpit 116, orbis 82 refs, tertius 60, hrön/hronir ~12) and interrupted — not done.
