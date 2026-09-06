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
| S1 | sidecar width by drag (grab handle on the zone's right edge) | todo | |
| S2 | OSD for volume/brightness — Andrew (mid-session): WANTED, and MORE prominent than a thin meter (headphone buttons change volume unseen); scroll on the rail's volume icon changes volume; a slider move in the popover SKIPS the OSD | todo | |
| S3 | hover-open on rail workspace numbers → strip of that ws's windows | todo | |
| S4 | notification actions inline on toasts | todo | toasts already render `n.get_actions()`; verify live, check hub history too |
| P1 | "paper" light palette variant; `astal-shell theme paper` reruns home:switch in bg | todo | |
| P2 | floorp userContent rules for lived-in sites from the palette | todo | |
| B1 | Library of Babel zen mode: hexagonal cells of drifting amber text, real book fragments | todo | |
| B2 | Funes launcher: frecency ranking of everything typed | todo | |

## Gates
- `mise shell:check` after each batch (ags bundle is the hard gate).
- `mise theme:gen` + `nix flake check` when the palette/render change (P1, P2).
- Live: `mise shell:dev` (pkill gjs first); screenshot with `grim -o eDP-1`.

## Decisions / gotchas discovered
- Board layout is 3 rows packed for 1920×1080 (DP-2): [NOW/WORKSPACES | WEATHER | CALENDAR/TODAY | POWER/SHELL], [PERF | AGENTS/MEDIA | DISK/NET], [JOURNAL | TOGGLES]. Andrew OK'd shrinking the board's type a notch (13/11/16) so it all shows — the ONE exception to sizes-bias-up.
- `mise shell:check`'s `ags types` step needs the network (npx) → fails in the sandbox; `ags bundle` alone is the hard gate.
- Sandbox has a PID namespace + blocks the Hyprland socket: live checks (pgrep gjs, hyprctl, grim, ags request) need the sandbox off.
- Live loop used: `pkill -x gjs; nohup ags run app.tsx &` from modules/desktop/shell, then `ags request -i astal-shell toggle dashboard`, `grim -o DP-2`.
