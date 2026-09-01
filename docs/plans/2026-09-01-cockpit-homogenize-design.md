# Cockpit Cleanup + Homogenize + Visual Spiff — Design

> **Status:** validated with Andrew 2026-09-01. Keep the current layout (spine ·
> rail · center thread-stack · tertius line) — this is a *cleanup + polish* pass
> inside it, not a re-architecture. Subordinate to
> `2026-08-30-orchestrator-cockpit-plan.md`; extends the workspace-scoping work in
> `2026-08-31-workspace-scoped-coordination-design.md`.

## Why — the diagnosis (from a 4-part code audit)

The cockpit feels "half-baked" because of one knot with four strands:

1. **Two chat UIs coexist.** The cockpit thread-stack AND a standalone `MachineChat`
   TUI (`mix console.machine_chat`, `machine_chat/loop.ex`) are both "the chat." The
   session pane surfaces the *old* one — that mystery right-hand roster is
   MachineChat's own CREW rail. Biggest single source of confusion.
2. **Verb sprawl.** Writing a message has 4 doors that all call `Channel.post`
   (`c` post / tertius `tell @x` / tertius bare-text `{:chat}` / the MachineChat
   composer), differing only in how the target thread is picked. Creating work has 4
   overlapping nouns (task/thread/ticket/note) with half-hidden create paths. `v`
   "chat" is mislabeled (it toggles the center PTY, doesn't chat). `Ctrl+N "new
   task"` in the reply hint is stale (belongs to MachineChat).
3. **The rail isn't workspace-scoped.** Only the center + tertius post follow the
   active workspace; MEMORY, NOW/Activity, STACK, ROSTER are global.
4. **Boards + Home are thin.** Rich data (`orbis.ex` computes per-workspace and
   per-thread rollups), text-wall rendering. Notes = bare bullets; Tickets = a
   vertical list mislabelled "columns" with unwired keys; Home = 3 lines/workspace;
   config = a keyboard-only text list. Boards are click-only (no keybinds).

## Decisions (validated)

- **Retire the standalone MachineChat TUI.** The cockpit thread-stack IS the chat.
- **The session pane shows the selected thread's real working agent PTY** (pi/claude
  doing the work) — the original "thread + live session side by side" intent — NOT a
  second chat app.
- **Order: cleanup first, visuals last** — A (scope) → B (collapse chats) → C
  (verbs) → D (visual spiff), so the visual layer lands on a stable, homogenized base.
- **Memory scoping:** facts/habits gain an optional `workspace_id`. `null` = global
  system knowledge (the seed self-facts); set = workspace-specific. The MEMORY panel
  shows global ∪ active-workspace. `bank_fact` inherits the thread's workspace.
- **Keep the layout.** No new columns/regions; polish within spine · rail · center ·
  tertius.

## Slice A — Scope the rail per workspace (cleanup, do first)

Make MEMORY, NOW/Activity, STACK, ROSTER follow the active workspace, mirroring the
center stack (`Channel.machine_threads(ws)` + `scope_workspace/2`).

- **Gates (NOW)** — trivial: `Thread` already has `workspace_id`; add
  `workspace_id \\ nil` + `scope_workspace/2` to `Workline.Ledger.statuses`, pass
  `active_workspace_id(state)` from `gates_read/0`.
- **STACK** — repoint `Console.Stack` at the **active workspace's repo path** (each
  workspace now carries its repo). ficciones → the monorepo; a client workspace → its
  own repo's git. This is exactly right for the client workspaces.
- **Activity events** — filter incoming Bus events by the active workspace in
  `push_activity/3` / `handle_info` (or subscribe per-workspace).
- **MEMORY** — schema change: add nullable `workspace_id` to `fact` + `habit`
  (migration); `coverage/pinned/pending_habits` gain a `workspace_id` param and
  filter `workspace_id IS NULL OR workspace_id = ?`; `bank_fact` sets it from the
  thread's workspace. Seed self-facts stay `null` (global).
- **ROSTER/ACTIVE** — `Session` has no workspace column; scope via a Thread join or a
  column. Lower priority (the CREW roster list is already workspace-scoped).

## Slice B — Collapse the two chats + fix the session pane

- **Retire `MachineChat`** (the standalone TUI + its `mix console.machine_chat` task +
  the cockpit window that runs it). Decompose when reached: audit what MachineChat
  does that the thread-stack doesn't (e.g. per-turn grouping, the composer) and port
  anything worth keeping into the thread-stack first.
- **Session pane → the agent's real PTY.** Repoint `Console.SessionPane` from the
  MachineChat window to the **lead agent's working terminal** (the pi/claude process).
  Resolve the lead's actual harness window, not the machine_chat reader.
- **Kill "leaves"** — `crew.ex:84` header `"leaves N/M"` → "crew"/"agents". (This is
  the only place the stale word renders; `Panel.Leaves` is already unplaced.)

## Slice C — Homogenize the verbs / vocab

One coherent small set:

- **Write = one door.** `c`/reply posts into the focused thread. The **tertius line is
  meta/orchestration only** — remove the bare-text→machine-thread `{:chat}` fallback
  (or make it an explicit "talk to the orchestrator"), not a silent 3rd chat door.
- **Create nouns, each with a first-class affordance (key + menu, not a buried
  tertius prefix):**
  - **Thread** — a unit of work/conversation with a lead (`n`). Retire the "task"
    label and the redundant `explore` verb.
  - **Workline** — a thread with an SDLC stage (promote / `build`/`spike`).
  - **Ticket** — backlog item, promotes to a thread. First-class create.
  - **Note** — scratch. First-class create.
- **Relabel `v`** "chat" → "term"/"session" (honest: it toggles the live PTY).
- **Drop the stale `Ctrl+N`** hint (dies with MachineChat).

## Slice D — Visual system (cards · color · menus)

A shared visual vocabulary applied across surfaces (done last, over the cleaned base):

- **A card primitive** — a small bordered box: title · status color · compact body —
  reused for workspace cards (Home), ticket cards (kanban), note cards, coworker cards
  (CREW).
- **A status color palette** — open / working / blocked / done / idle — used
  consistently everywhere a status shows.
- **Home = a real dashboard.** Use the rollup data already computed (`orbis.ex`):
  per-workspace cards with status tiles + the per-thread rows currently thrown away.
- **Tickets = a true kanban** (side-by-side columns of cards) with the advertised
  `⏎/j/k/p` keys actually wired.
- **Notes = cards** (not bullets); first-class create/edit.
- **Config via menus** — generalize the existing right-click `menu` into a reusable
  popup-menu component for config/actions; give boards keybinds + cursor state (fix
  the click-only reachability gap).

## Execution notes

- TDD per task; both module suites + compile `--warnings-as-errors` green per commit;
  the machine gate (`flake:check`/`home:switch`) is Andrew's.
- Decompose B/C/D when reached (this repo's design→slice pattern). Slice A is
  decomposed above and executes now.
- Live PTY bits (session-pane repoint) = Andrew's kitty pass, same bar as before.
