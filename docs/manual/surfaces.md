# Surfaces

Two surfaces, one generated palette.

| Surface | Where | Day-to-day job | Open it |
|---|---|---|---|
| **nvim-config** (Neovim) | `~/projects/nvim-config`, linked at `~/.config/nvim` | code · diffs · review | `nvim` |
| **shell** (astal) | `modules/desktop/shell` | rail, bar, launcher (`>` verbs), the deck, notifications, OSD, lock, theme toggle | always up (`astal-shell.service`) |

**Rule of thumb.** If it is about *the code* (read it, edit it, review the diff), you are in
Neovim. If it is *the machine* (volume, workspace, a verb, a toast), the shell.

## The shell's wheel

The scroll wheel means one thing per place, and the same thing wherever it appears.

| Over | The wheel does | Step |
|---|---|---|
| the rail's workspace strip | switch workspace | one per notch |
| the bar's window strip | focus the next or previous window in the strip, stopping at the ends | one per notch |
| the bar's battery cell | brightness | 5 % |
| the rail's volume item | volume | 2 %, capped at 100 % |
| the deck's now-playing cell | volume (the same function) | 2 %, capped at 100 % |
| anywhere else | nothing; the launcher has no wheel on purpose | |

## What opens on hover, what on click

| Cell | Opens on | Notes |
|---|---|---|
| the rail's workspace strip | Super held + hover, after `feel.superHoverMs` (250 ms) | a plain click goes to that workspace |
| every other bar and rail cell (clock, weather, volume, network, perf...) | click | sliding to a neighbour while one is open swaps at once |
| the deck's now-playing title | click | the media card |
| the deck's log, the Aleph | click | toggles the drawer, the dashboard |

The dwell, the grace after the pointer leaves and the hot edge are in Settings, under FEEL.

**The shell makes sound.** A short effect plays when a session starts waiting on you, when a long
turn lands, and when a deck timer or pomodoro phase ends (`lib/sfx.ts`, through `pw-play`).
Setting `sound.sfx` (Settings, "sound effects"; on by default) turns it off, and do-not-disturb
mutes it, as it mutes toasts. The WAVs live in `modules/desktop/shell/assets/sfx/`.

**The rail clock has its jokes.** It reads the time through `clockFace` (`lib/clock-core.ts`):
at 4:04 it says `404` (the time cannot be found), at 3:14 `π`.

**The bar's orchestrator cell says what waits on you.** `▲ N · orchestrator: <state>`: N is the
length of `needs_you` in `$XDG_RUNTIME_DIR/babylon/board.json`, the state is
the orchestrator's session record (working, waits on you, idle, restarting, off). A click opens
arena on its inbox (`arena inbox`). `SUPER+U` opens a one-line entry, `tell the orchestrator ❯`: Enter
runs `babylon tell "<line>"` and closes it (the cell then says `on it`, then `answered`, until its
next click); a refusal stays in the entry with babylon's reason; Esc sends nothing.

**Each item in `needs_you` is a desktop notice** (`lib/needs.ts`): `▲ N need you` over the item's first row,
raised once per item id, taken back when the id leaves `needs_you`, and not raised while arena's window
has focus. A click on the body runs `arena board <ticket>` (`arena inbox` for an item with no ticket); the
buttons are the item's actions that have an argv (go/no, an ask's options), run as given. Words and picks stay in arena.
