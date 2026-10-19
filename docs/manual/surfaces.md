# Surfaces

Three surfaces, one brain. Every one reads the same `Server.*` contexts over the same Bus and
wears the same generated palette; none owns state.

| Surface | Where | Day-to-day job | Open it |
|---|---|---|---|
| **asterion** (Neovim) | `~/projects/asterion`, linked at `~/.config/nvim` | code · diffs · review · the Tlön sidebar, thread buffers and composer · a coworker terminal | `nvim`, then `<leader>oo` |
| **office** (TUI) | tlon's `office/` | the pixel-art room over the server: who works, who waits on you, the worklines; every thread, coworker, ticket, triage, health and schedule a key away | `tlon` |
| **web** (LiveView) | `modules/server/lib/server/web` | the same sidebar · thread · composer in a browser, live on the Bus — from a phone over tailscale | `mise run server:web` → http://127.0.0.1:4042 |
| **shell** (astal) | `modules/desktop/shell` | rail, bar, launcher (`>` verbs), deck panes (Agents…), notifications, OSD, lock, theme toggle | always up (`astal-shell.service`) |

The server (`modules/server`, `tlon.service`) is not a surface: it is the record — threads,
facts, checks, todos, worklines — and the MCP channel the coworkers speak. The operator reaches
it from any surface; from a shell, `mise run server:dossier -- <id>` and `server:post`.

**Rule of thumb.** If it is about *one thread's work* (read it, reply, review the diff, watch
the coworker), you are in Neovim. If it is *everything at once*, the office. If it is *the
machine* (volume, workspace, a verb, a toast), the shell.

## The shell's wheel

The scroll wheel means one thing per place, and the same thing wherever it appears.

| Over | The wheel does | Step |
|---|---|---|
| the rail's workspace strip | switch workspace | one per notch |
| the bar's window strip | focus the next or previous window in the strip, stopping at the ends | one per notch |
| the bar's battery cell | brightness | 5 % |
| the rail's volume item | volume | 2 %, capped at 100 % |
| the deck's now-playing cell | volume (the same function) | 2 %, capped at 100 % |
| anywhere else | nothing; the office canvas and the launcher have no wheel on purpose | |

## What opens on hover, what on click

| Cell | Opens on | Notes |
|---|---|---|
| the rail's workspace strip | Super held + hover, after `feel.superHoverMs` (250 ms) | a plain click goes to that workspace |
| every other bar and rail cell (clock, weather, volume, network, perf...) | click | sliding to a neighbour while one is open swaps at once |
| the deck's now-playing title | click | the media card |
| the deck's log, the Aleph | click | toggles the drawer, the dashboard |

The dwell, the grace after the pointer leaves and the hot edge are in Settings, under FEEL.

**The shell makes sound.** A short effect plays when a decision alert arrives, when a tlon
landing lands, and when a deck timer or pomodoro phase ends (`lib/sfx.ts`, through `pw-play`).
Setting `sound.sfx` (Settings, "sound effects"; on by default) turns it off, and do-not-disturb
mutes it, as it mutes toasts. The WAVs live in `modules/desktop/shell/assets/sfx/`; the landing
chime is the same one the Claude Code plugin plays, and the landing toast says what the plugin's
does: the server's own alert row (`#<id> landed — <title>`).
