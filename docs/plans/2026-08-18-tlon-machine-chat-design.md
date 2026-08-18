# Tlön machine-chat — an interactive, foldable transcript tab

**Date:** 2026-08-18
**Status:** design approved (brainstormed with Andrew)
**Supersedes:** the `aleph.machine_log` dumb-stream tab (Pass 1 polish), whose grouping
logic is lifted into the shared renderer here.

## Why

The Tlön `chat` window today is a `tail -f`-style append-only stream (`aleph.machine_log`):
clean, but a flat wall of messages with no way to fold, focus, or scan history. Andrew wants
it to become **"Chorus for the Tlön space"** — an interactive, collapsible view — and for it
to **share code** with the cockpit's `Chorus` panel rather than fork a second renderer.

## Decisions (locked in brainstorm)

- **Home:** a standalone raxol/termbox TUI running in the `chat` tmux window (the Tlön strip,
  next to `pi`/`claude`), NOT a cockpit panel. Keeps it in the harness strip.
- **Liveness:** polls the shared SQLite db at `FUNES_DB` (~700 ms), reader-role
  (`start_mcp: false`, `start_switchboard: false`, Ecto logs silenced) — because `Funes.Bus`
  is node-local and this is a separate OS process. Same constraint as Pass 1.
- **Fold unit:** a whole thread block.
- **Block source:** machine-scope threads only (`scope == "machine"`), current + rotated,
  newest-activity first. Newest expanded, older collapsed by default.
- **Inside a block:** Pass 1 turn-grouping (author bursts under one header) + day dividers.
- **Interactions:** `↑↓`/`jk` move the selected block, `Enter`/`Space` fold↔unfold,
  `z` zoom the selected thread to full-pane, `Esc` back, `q` quit; scroll on overflow;
  auto-follow newest only when already at the bottom.

## Architecture

The `chat` window runs a new Mix task `aleph.machine_chat` — a self-contained termbox TUI
reusing aleph's existing host machinery (the patched `tb_resize/0` NIF, the `Aleph.Panel`
`{text, style}` row model, the alt-screen lifecycle proven in `Aleph.Cockpit`). What's new is
a small host owning interaction state and driving two event sources: a poll timer and stdin.

"Shared code" is honored by **extraction**, not by overloading `Chorus`: the pure
row-rendering moves into a new `Aleph.Transcript` module that both this tab and (as a
follow-up) `Chorus` call. Pass 1's grouping logic becomes `Aleph.Transcript`'s core,
re-expressed as `{text, style}` rows instead of ANSI.

## Components

1. **`Funes.Channel.machine_threads/1`** (new funes export) — all machine-scope threads
   (not just the latest open), newest-activity first, each with messages. Mirror of
   `chorus/1` but `scope == "machine"` and without the open-only filter. The one addition to
   funes' public surface (`:boundary` export list in `lib/funes.ex`).

2. **`Aleph.Transcript`** (new, pure) — `blocks + view_state → [row]`. Owns turn-grouping,
   day dividers, hanging-indent body wrap, and collapsed forms: a folded thread → one
   `▸ title  (n)` row; an expanded thread → header + grouped turns; zoom → only the target
   thread, full-pane. Zero IO, fully unit-testable.

3. **`Aleph.MachineChat.Host`** (new GenServer) — owns
   `%{blocks, selected, folded: MapSet, scroll, zoom: id | nil, follow?: bool}`. Handles a
   `:poll` tick (re-read + **merge**, preserving folds) and key events. Its state transitions
   (`merge/2`, `handle_key/2`) are extracted as pure functions so they test without the
   GenServer.

4. **`aleph.machine_chat`** (new Mix task) — reader-role boot + termbox host loop.

**Data flow:** poll → `machine_threads/1` → `merge` into state (folds survive; new threads
take the default) → if `follow?` and at-bottom, pin scroll to newest → `Transcript.render` →
paint. Key → mutate state → repaint. Zoom is a render-time filter, not separate rendering.

## Error handling & edge cases

- **Boot failure:** print one error and exit (tmux shows it; `aleph:run` self-heal restarts).
- **Transient poll failure:** caught and skipped — last good frame stays on screen. A stale
  but readable transcript is the right failure mode for a glance tab.
- **No machine threads:** dim placeholder, not a blank pane.
- **Rotation:** a new machine thread appears expanded and the previous auto-collapses ONLY if
  the user hadn't manually toggled it — manual fold state (by thread id) always wins.
- **Follow-tail:** `follow?` starts true; a poll with new messages pins to newest only when
  at the bottom; if scrolled up, position is untouched until the user returns to the bottom.
- **Zoom + fold:** zoom always shows the thread expanded; `Esc` restores prior list
  scroll/selection; folding is a no-op while zoomed.
- **Resize:** `tb_resize/0` each tick; `Transcript` re-wraps to the new width (reflow free).
- **Colors:** the Pass 1 author palette carries over (known hand-picked, others hashed), now
  expressed as styles.

## Testing

Pure and headless, matching aleph's law (unit-test the seams; never the TTY/GenServer):

- **`Aleph.Transcript` (unit, the bulk):** table-driven over `blocks + view_state → rows` —
  turn-grouping merges a burst; a >5-min gap re-headers; day rollover emits a divider; a
  folded thread → one `▸ title (n)` row; expanded → header + turns; zoom → only the target;
  width changes reflow. The Pass 1 assertions, lifted and now actually testable.
- **Fold-state merge (unit):** `merge(state, fresh)` — folds survive a poll; a new thread
  takes the default; a manually-unfolded old thread stays unfolded across rotation.
- **Key reducer (unit):** `handle_key(state, key) → state` — jk bounds, Enter toggles the
  MapSet, `z`/`Esc` set/clear zoom, folding no-ops while zoomed.
- **Not unit-tested:** the termbox host loop, stdin, poll timer (same exclusion the cockpit
  documents). Verified live via `uqbar` on the `chat` window.
- **Gate:** `mise run aleph:check` green + `machine_threads/1` covered on the funes side.

## Build order

1. `Funes.Channel.machine_threads/1` + funes export + test.
2. `Aleph.Transcript` (TDD: tests first) — lift Pass 1 logic as rows.
3. `Aleph.MachineChat.Host` pure reducers (`merge/2`, `handle_key/2`) + tests.
4. `aleph.machine_chat` Mix task (termbox host loop) — wraps the reducers.
5. Point the cockpit's `chat` window at `aleph.machine_chat`; retire `aleph.machine_log`.
6. `mise run aleph:check` green; live-verify via `uqbar`.
