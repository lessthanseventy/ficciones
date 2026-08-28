# Reshape Slice C: Read-Models — Real Membership + the Unified Thread List

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The server-side read-models the Slack-shaped UI will sit on: real per-workspace thread grouping (killing the "first world takes all" floor), and ONE unified thread list per workspace where chat threads and tracked threads are the same kind of row.

**Architecture:** (C1) `Aleph.Orbis` rows carry `world_id` and `worlds/2` groups by it. (C2) `Funes.Board.sidebar/0` — the sidebar read-model: per workspace, its open threads (root first, then by last activity; each row carries stage/awaiting/lead/working/last_at) and its crew with working flags. (C3) `Aleph.Panel.Threads` replaces `Panel.Leaves` + `Panel.Workline` in the world carousel — the unified list rendered: `title · ▸stage / ⏸gate / ⚠blocking`, `⋯` when working. Leaves/Workline panels die.

**Context:** Design docs/plans/2026-08-27-clarity-rename-slack-shape-design.md ("three read-models"; "a thread may be tracked = has a stage"). Slice A made `thread.world_id` real; slice B unified promotion. Orbis' coarse attribution is documented at `modules/aleph/lib/aleph/orbis.ex` ("the first world carries all machine leaves").

---

### Task C1: Orbis groups by real membership (TDD)

`orbis.ex`: `row/1` adds `world_id: thread.world_id`; `worlds(rows, refs)` groups rows by `world_id` (a row matching no ref lands in the first ref — post-slice-A this is belt only). Tests in `orbis_test.exs`: two worlds each get their own rows/summaries; unmatched row defaults to first. Update the stale "coarse attribution" moduledoc. Commit.

### Task C2: `Funes.Board.sidebar/0` (TDD)

Returns `[%{workspace: %{id, name}, threads: [...], crew: [...]}]` per world (oldest world first): threads = OPEN threads with that `world_id`, any scope, root flagged `root: true` and sorted first, then last-activity desc; each `%{id, title, root, stage, awaiting, lead, working, last_at}` (lead via `Channel.thread_lead/1`, working via `Funes.Presence.Thinking.thinking_for/1`, last_at = newest message created_at or thread created_at). crew = the world's roster entries with a `working` flag (any thinking declared by that name, `-machine` suffix tolerated). Tests: grouping, root-first ordering, stage riding through, working flags. Commit.

### Task C3: `Aleph.Panel.Threads` replaces Leaves + Workline (TDD)

New panel module (THREADS): rows `▸/· title · stage-chip` with `⏸ awaiting x`, `⋯ working`, lead tag; pick → `{:focus_thread, id}`; hints j/k ⏎. Cockpit read `threads:` assembled from `Funes.Board.sidebar/0` filtered to the active world. `Space.space_from_world` right column becomes `[Health, Crew, Activity, Threads]`; delete `Panel.Leaves` + `Panel.Workline` + their view title entries + tests; update view/keymap/cockpit tests that index the carousel. Gates: `mise run check` + flake. Commit.
