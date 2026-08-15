# aleph — TUI kickoff (the cockpit over funes)

Handoff note for the phase that puts a face on funes. Written 2026-08-15 at commit
`ac8a4e8`, after the coordination foundation + reactive substrate landed and passed
three fresh-eyes reviews. Read `docs/plans/2026-08-14-aleph-cockpit-and-elixir-spine.md`
(the design) and `modules/funes/AGENTS.md` (what's built) first; this only tees up
the decisions the TUI phase opens with.

## Runnable state today (be honest about it)

funes is a **headless OTP app** — all plumbing, no face:

- No `mix funes`. Only `mix funes.doctor` (the integrity report). Drive everything
  else from `iex -S mix` against the contexts.
- Starting the app boots `Phoenix.PubSub` + SQLite. `Switchboard.Server` is **opt-in**
  (`config :funes, :start_switchboard` — off by default); the arbiter defaults to
  `Funes.Arbiter.Inert` (pokes nothing).
- `Funes.Board.in_scope/1` and `Staff.roster/0` **return data structures — nothing
  renders them.** That renderer is this phase.

## The architecture, settled (so "Herdr as a display?" doesn't recur)

Three roles, no overlap:

- **aleph = the face.** The cockpit TUI the human dwells in. Subscribes to funes
  topics, renders the read models. Holds no truth (§7 — a view over the contexts).
- **the arbiter = the hands.** A *capability* (Herdr | tmux | ghostty embed) that
  spawns / pokes / hops-into the real panes agents run in. Herdr is NOT the display;
  it is a pane-manager aleph drives through a thin adapter (`Funes.Arbiter`).
- **funes = the memory.** The core both read from; SQLite is the truth.

So the shape is: **build our own TUI** (a meta-app that starts the funes app, renders
the board, and calls the arbiter for pane work) — not funes-driving-Herdr-as-display.

## What is READY to render (no new funes code needed for a first board)

- **IN SCOPE**: `Funes.Board.in_scope(thread)` → `%{north_star, lead, shipped,
  learnings, blockers: %{shown, more}, chatter}`, capped (§6).
- **IN FLIGHT**: `Funes.Staff.roster()` → live sessions × `%{agent, thread_id,
  thread_title, workspace_ref, warm?}`.
- **Live updates**: subscribe `Funes.Bus.subscribe_thread(id)` (IN SCOPE),
  `subscribe_sessions()` (IN FLIGHT), `subscribe_threads()` (the list). Every write
  already broadcasts a typed event.
- **Capture path**: `Funes.Channel.post/1` (the human posts; the SUGGESTION BOX).

Not ready (deferred, need their own work): **ACTION REQUIRED** and **RUNWAY**
(context-pressure) — they need the `Sense` collectors and a pressure gauge; **queue /
ACTION ITEMS** — no table backs it yet; **NORTH STAR** beyond the thread title.

## Decisions to open the phase with

1. **TUI framework.** `Ratatouille` is the established Elixir TUI (The Elm
   Architecture over termbox). The design also floats "Drafter, a LiveView-shaped
   TUI" and a later Phoenix LiveView **web** GUI (§7 says the same contexts support
   both). Recommend: prove the panes with Ratatouille first; keep the render layer
   thin so a LiveView web view is a second consumer later, not a rewrite.
2. **Arbiter backend to build first.** `tmux` is the simplest real one (scriptable
   `send-keys`, `new-session`, `capture-pane`) and is the clean `Inert → real` step.
   Herdr is the human's own tool; a ghostty embed is heavier. Recommend tmux first —
   BUT it stays inert-equivalent until the **engine-credit presence signal** lands
   (the last wake-gate; never poke a clocked-out session, §3b).
3. **Where aleph lives.** `modules/aleph/` (its own module depending on funes —
   matches "aleph is first-class, the third Borges module") vs. inside funes for now
   ("a module is born when it has content"). Recommend: start the TUI inside a small
   `aleph` module the moment it has real content; do NOT create an empty placeholder.
   Keep the funes boundary intact — aleph depends on funes, funes never on aleph.
4. **The §8 boundary holds.** aleph may read funes' public context functions and
   subscribe to its topics; it must not reach into funes' tables or internals.

## Suggested first slice (verifiable by looking at it)

A **read-only** board: a Ratatouille app that (a) starts the funes app, (b) renders
`Staff.roster()` and one thread's `Board.in_scope/1`, (c) subscribes to that thread's
topic + `funes:sessions` and re-renders on events. No arbiter yet — view-only, so it
is verified by watching it update as you `Channel.post/1` from another shell, not by
the green gate. Then add "hop into session" (the arbiter) once presence-gated.

## The two long poles after a first board

- **A real terminal arbiter** (tmux) to make the wake + "hop into a session"
  actuate — gated on the engine-credit presence signal.
- **The `Sense` collectors** (PR/calendar/…) to light up ACTION REQUIRED and the
  daily-note surfaces (§6), each honest about its `collection` row.
