# One machine, and the session record

Written 2026-11-14. Holds what the pieces on this machine are *for*, so a new idea has somewhere to
go, and the one contract that ties their views of agents together.

## What it is for

One person's computer where agents belong to the machine: **you always know who is doing what and
what needs you, you can trust what they hand back, and it is a good place to spend the day.**

Three promises, and every piece serves at least one:

| Promise | Asks | Kept by |
|---|---|---|
| **Awareness** | who is doing what; what needs me | arena's marks, the deck's sessions cell and roster, Alerts, the changes pane, the statusline |
| **Trust** | can I believe what came back | menard (no half-applied edit, one JSON line per run), tlon's pipeline (nothing lands unchecked), the four rules (`modules/agents/how-to-work.md`) |
| **Delight** | do I want to be here | the office and its cast, the palettes, arena's turning gradient, the chimes |

## The layers

Every layer is a view of the same thing, a Claude Code session, at a different distance:

| Layer | What it is | What it shows of the sessions |
|---|---|---|
| ficciones | the machine | builds and wires all of it; installs the rules and the hooks |
| inside a session | Claude Code, menard, the mods, the statusline | one session, up close: each call, the diff, the context |
| arena | the tmux strip | your sessions as places to go |
| the shell | bar, deck, Alerts, office rail | all of them at a glance, and what needs you |
| tlon | the crew | sessions with a manager, a pipeline and a door |

tlon is two things that grew together: the **office** (a view: awareness, delight) and the **org**
(roles, tickets, the pipeline: trust). The org is its core; the office is one view among the others.
The crew is sessions that have a manager.

## The session record

Each Claude Code session, yours or a coworker's, keeps a record in `$XDG_RUNTIME_DIR/sessions`.
One writer per file:

| File | Writer | Holds |
|---|---|---|
| `<session_id>.json` | `modules/agents/session-state.sh`, on every hook event | `state` (`working`, `done`, `waiting`), `since`, `at`, `cwd`, `repo`, `socket` and `pane` (tmux), `said` (the last ask), `doing` (the last call) |
| `<session_id>.meter` | `modules/desktop/scripts/statusline-box.sh`, on a change | `ctx` (% of the compaction budget), `model` |

The same hook sets the pane option `@arena_claude`, which is arena's view of the state. The session's
end removes both files; a reader drops a record whose tmux pane is gone.

Readers: the deck's sessions cell (`lib/sessions.ts`, by inotify) shows yours in arena's marks, rings
when one starts waiting, chimes when a long turn lands, and takes you to its pane. A session on a
`tlon-workspace-*` tmux server is the crew's and is left to the roster.

## Where a new idea goes

Ask which promise it keeps and which layer it is a view in. If it needs to know what a session is
doing, it reads the record; it does not grow a hook of its own. If it needs something the record
lacks, the field goes in the record, written by the one place that knows it.

## Open

- **The office under arena draws in half blocks.** tlon's office falls back from kitty graphics
  whenever it sees tmux (`tlon/office/tui/boot.ts`), and arena, which draws panes itself and already
  handles kitty pictures, gets the low-resolution room.
- **The crew's records are unseen so far.** Seats load the user's hooks beside their `--settings`,
  so they should write records on their own servers; no seat has run since the hook landed.
- **A session outside tmux that crashes leaves its record** until the runtime dir is cleared: there is
  no pane to check it against.
- **menard's marks pile up in `/tmp`** (`menard-format-*.log`, `menard-door-*`, hundreds of them),
  which is menard's own bookkeeping and stays out of the record.
- **arena could show the crew**: it reaches one tmux server at a time; the records name every server.
