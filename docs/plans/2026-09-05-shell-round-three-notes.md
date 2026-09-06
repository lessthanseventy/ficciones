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
