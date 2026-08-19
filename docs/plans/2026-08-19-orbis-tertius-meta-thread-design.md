# Orbis Tertius — the machine meta-thread & orchestrator

Date: 2026-08-19
Status: all 5 slices landed (foundation · dashboard · agent · cross-thread read · cadence). Tlön was
also simplified to a three-window cast — **uqbar** (the console/doorway) · **hronir** (the builder,
real Claude) · **tertius** (the center, the meta agent) — the nouns of "Tlön, Uqbar, Orbis Tertius."
The standing pi worker was dropped; tertius is now the center coworker (the `tertius` profile,
socket `aleph-tertius`, session `tlon`). Live eyeball pending after `aleph:reset`.

## Problem

Tlön's machine threads are **flat siblings** with no meta layer. The "machine thread" is not a
first-class concept — `Funes.Channel.machine_thread/0` is `order_by: [desc: t.id], limit: 1`, i.e.
"the newest open machine thread." Before B1.4 there was only one machine thread, so this was fine.
After B1.4 (staffed per-thread sessions — thread 2, the joke thread, etc. are all machine-scope),
`machine_thread/0` now returns **the newest staffed leaf**, not the standing coworkers' home. That
is the fragility under the 2026-08-19 duplicate-delivery bug: `standing_thread_id` can capture a
leaf.

Operator intuition (Andrew): there should be a *meta thread over the whole Tlön space* — a "leader
of the leaders." That concept doesn't exist; it would be genuinely new structure.

## Naming (Borges layering — three distinct things)

- **Aleph** — the cockpit itself (the TTY; Borges' point that contains all points). Exists.
- **Orbis** — the *chorus view*: all threads in one feed (`Aleph.Panel.Chorus`, "ORBIS · all
  threads"). Exists, project-scoped; we point a machine-scoped instance at Tlön. The **dashboard**.
- **Orbis Tertius** — in the story, the secret society that *authors and orders* Tlön. This is the
  meta **agent**: handle **`tertius-machine`**, the "leader of leaders." Orbis = the view, Tertius =
  the agent who works through it — keeps view-vs-agent from fusing.

## Concept model

- **Root meta thread** — a distinguished, never-rotated machine thread. `tertius-machine`'s
  permanent home and the operator's seat for working on Tlön itself.
- **Leaf threads** — staffed worker threads (B1.4). Still flat rows in the DB; the *root* is the
  one with cross-thread read + the orchestrator seat. No `parent` column, no migration.
- **Distinction of the root** (no schema change):
  - Foundation: the **oldest open machine thread** (`order_by: [asc: t.id], limit: 1`) — the
    founding machine thread; leaves are always newer. Restores the pre-B1.4 intent.
  - Authoritative (once the agent lands): the machine thread **led by `tertius-machine`**
    (`agent_id` → name). Reuses the existing `agent_id`; the two signals agree. The root is never
    closed by rotation / `clear-machine-threads`.

## v1 scope (agreed): vantage + synthesis, both a live agent AND a dashboard

1. **Live agent** — `tertius-machine` bound to the root thread, whose job is to read across the
   leaves and post briefings / flags / conflicts into the root thread.
2. **Dashboard** — a machine-scoped Orbis chorus + a rollup lens (open / stalled / done, per-thread
   leads, conflicts) in the cockpit. **Home (agreed 2026-08-19): inside the Tlön space — NOT a new
   space.** Two surfaces: a compact **rollup panel** in the Tlön sidebar (reshaping the weak
   panels — Logbook/Habits earn their slot poorly, Settings can be reshaped) and a **full
   machine-Orbis tab** in the Tlön tmux session (a cousin of `Aleph.MachineChat.Loop`, showing every
   leaf's feed). Latitude granted to surface whatever makes sense wherever it fits. Rejected: a
   standalone switcher space.

Deferred: **autonomous dispatch** (tertius spawning/staffing/reaping leaves) — only once manual
dispatch actually hurts. Do not build the authority layer on a lifecycle that just had a
duplicate-delivery bug.

## Reuse map (the key constraint — share code with the Orbis/chat side)

Almost nothing here is new machinery; it is the existing coworker + chorus stack re-pointed:

| Piece | Reuses |
|---|---|
| Dashboard feed (2b, the `chat` tab) | `Aleph.MachineChat.Loop` over `Funes.Channel.machine_threads/1` — already the machine chorus |
| Dashboard rollup (2a, the panel) | NEW `Aleph.Panel.Orbis`, but its status derives from the existing `Funes.Board.in_scope/1` (same brief Triage reads) — no new funes read |
| Agent spawn / binding | `spawn_agent_window` / `claude_launcher` / `FUNES_*` env, exactly like a B1.4 `t<id>` session |
| Wake / addressing | `Aleph.Mention` (the router fixed on 2026-08-19) |
| Feed rendering | `Aleph.MachineChat.Loop` / `Aleph.Transcript` (chat tab is already "a minimal cousin of Aleph.Cockpit") |

Genuinely new:
1. **First-class root thread** — `Funes.Channel.machine_thread/0` re-pointed to the OLDEST open
   machine thread (was newest). No new function / no caller changes: aleph's four callers all want
   the standing/meta thread, which is the root. *(This slice.)*
2. **`tertius-machine`** coworker — handle in `Aleph.Mention.@base_coworkers`, a profile, spawned on
   the root thread at boot.
3. **Cross-thread read** — tertius must read the leaves. `get_messages` is self-thread only;
   `consult_peer` / `get_dossier` are the cross-thread verbs. Verify coverage; add a minimal
   `machine_overview` read tool only if there's a real gap.
4. **Cadence** — tertius wakes on @-mention and on operator posts to the root; a leaf's
   `record_done` / close nudges a synthesis. No noisy periodic loop in v1.

## Slices

1. **Foundation** *(this pass)* — `Funes.Channel.machine_thread/0` re-pointed to the oldest open
   machine thread + funes test. aleph's `standing_thread_id` / meta uses now resolve to a stable
   root, never a staffed leaf. Standalone; also hardens the 2026-08-19 bug area.
2. **Dashboard** *(inside Tlön, not a new space)* — two surfaces:
   - **2a. Rollup panel** *(done 2026-08-19)* — `Aleph.Panel.Orbis`, a pure rollup lens over every
     machine thread (root + leaves): a summary line (open / stalled / done, conflicts) + one row per
     leaf (lead · status, stalled leaves trailing their conflict count). Status derives from
     `Funes.Board.in_scope/1` (real blockers/failed checks, never a self-report). Seated in the Tlön
     right sidebar **in the slot Logbook held** — `right: [Health, Orbis, Habits]`. Logbook is now
     orphaned from the layout (module still wired via `logbook_read`); full retirement is a
     follow-up. aleph:check 303/0.
   - **2b. Tab rollup** *(done 2026-08-19)* — the existing `chat` tab
     (`mix aleph.machine_chat` → `Aleph.MachineChat.Loop`) is ALREADY the machine chorus over every
     leaf; 2b pins the same rollup line as a one-row header strip above its feed. Semantics extracted
     to a shared `Aleph.Orbis` (rollup data — `status/2`, `summarize/1`, `rollup/0`), used by BOTH
     the cockpit read and the loop so a status rule can't drift; the strip reuses
     `Aleph.Panel.Orbis.summary_row/1` (now public) so both surfaces paint the identical line. The
     TTY paint is live-only (aleph's law) — eyeball at the cockpit after `aleph:reset`; the data +
     strip-row build are verified (aleph:check 308/0, live read-only eval).
3. **Agent** *(done 2026-08-19)* — `tertius-machine`, spawned on the root at boot. **Harness (agreed):
   a cheap glm-5.2 pi window** (not real Claude — keeps a distinct model from claude-machine and a low
   idle cost), with the meta-agent persona as its profile `system_prompt`. Pieces: handle→window in
   `Aleph.Mention.@base_coworkers` (`tertius-machine` → `tertius`); a `tertius` profile
   (`Aleph.Profiles`, mirrors tlön's machine-citizen surface + `@tertius_role`); `pi_command/1`
   extracted so both the space center and a windowed pi share one launcher; `spawn_tertius_window` +
   `ensure_tertius_coworker` ride the render preamble (a `new-window` pi on the `aleph-tlon` server,
   bound to the root via `Spawn.join`, gated + retried like the claude window). claude-machine stays
   the root's interactive lead; tertius wakes only on `@tertius-machine` (never the bare-reply lead
   fallback), so it's the quiet vantage, not a second answerer. Cross-thread READ of the leaves is
   still slice 4 — until then tertius posts to the root and reads its own dossier. Verified: aleph:check
   312/0 + a live eval of the launch string; the actual glm window is a live eyeball after `aleph:reset`.
4. **Cross-thread read** *(done 2026-08-19)* — tertius can now see the leaves. `get_messages`/
   `get_dossier` are self-thread by the "no tool takes a thread parameter" invariant, so rather than
   break it: `Funes.Channel.open_machine_threads/0` + `Funes.Board.machine_overview/0` (each open
   machine thread as a compact brief — lead, next, blockers, recent messages — from the same
   `in_scope/1` aggregate) + a `machine_overview` MCP tool that takes NO thread param and is served
   ONLY to a machine-scope connection (a project agent is refused; project/closed threads never leak
   in). Wired into tertius's profile (`@tertius_funes_mcp` = tlön's surface + `machine_overview`) and
   its persona points at it. Verified: funes 232/0, aleph 313/0, a live read of the dev DB.
5. **Cadence** *(done 2026-08-19)* — a machine LEAF closing (`:thread_closed`, machine-scope, not the
   root) nudges the tertius center to run `machine_overview` + refresh the root rollup. Chosen because
   `:thread_closed` reaches the cockpit globally (threads_topic), whereas `record_done`'s
   `:event_recorded` is thread-scoped and doesn't — so a record_done-without-close trigger is a
   documented follow-up (needs a funes Bus tweak). Plus `@tertius-machine` on demand (always). No
   periodic loop.

## Verification

`mise run aleph:check` (format + warnings-as-errors + headless) green per slice; funes unit suite
for the funes change. Live behavior (spawn, wake, dashboard) verified at the cockpit after
`aleph:reset`, since the BEAM does not hot-reload.
