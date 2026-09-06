# Shell round three — running notes (2026-09-05)

Andrew asked for ALL of these in one go; low on his 5h chunk, reset in <1h, so this file is the
resume point. Branch `astal-shell`. Each item lands as its own small commit. Update the status
column as work lands.

## The list

| # | item | status | notes |
|---|------|--------|-------|
| D1 | per-core sparklines + killable process list (click-to-kill, cpu/mem sort toggle) | todo | |
| D2 | DISK card (df per mount as meters) + NET card (wifi signal history, SSID, IP) | todo | |
| D3 | TODAY card: missed notifications + khal agenda + agents awaiting, one "needs me" list | todo | |
| D4 | JOURNAL card: last few journalctl lines at warning+ | todo | |
| D5 | WORKSPACES overview card: every ws with window icons, click to jump | todo | |
| S1 | sidecar width by drag (grab handle on the zone's right edge) | todo | |
| S2 | OSD: thin amber meter along the bar's underside for volume/brightness | todo | |
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
