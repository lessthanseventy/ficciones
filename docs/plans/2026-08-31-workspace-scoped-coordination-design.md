# Workspace-Scoped Coordination + the Thread/Session Split — Design

> **Status: BUILT 2026-08-31** (all 6 tasks, on `main`, server 459/0 + console 885/0,
> both compiles `--warnings-as-errors` clean). Live DB rosters seeded. REMAINING:
> Andrew's restart (`console:run`) + kitty pass on the session-pane PTY (render/key
> routing/click/resize — the live seam), and the machine gate (`flake:check`/`home:switch`).
> Subordinate to
> `2026-08-30-orchestrator-cockpit-plan.md` (this fills in Slice 3's "re-scope
> everything" acceptance gap + the Slice 4 lead-as-manager UX). When this and the
> cockpit plan disagree, the cockpit plan wins on model, this wins on the specifics
> below.

## Why

Two live bugs, one root. Switching workspace (WS1 `ficciones` → WS2 `ex_riverside`)
left the **center thread-stack unchanged** — it still showed WS1's thread. And the
top window strip's tabs looked like they should switch content but did nothing.

Root causes:

- **The center is global, not workspace-scoped.** `cockpit.ex` reads
  `Channel.machine_threads()`, and `machine_threads/1` selects *every*
  `scope=="machine"` thread with no workspace filter. The whole "machine chat" is a
  single global root thread (`machine_thread/0` picks the first open machine thread
  DB-wide) — built before multi-workspace existed. WS2 has no machine thread at all.
- **The top strip is the legacy tmux window / lead strip**, decoupled from the
  center. Clicking a tab (`{:select_tab, n}`) just moves tmux window focus and
  returns state unchanged — the center is never touched.

The fix isn't a patch; it's finishing the coordination model: make threads
workspace-scoped, give every thread a lead from birth, and show a thread's live
agent session as a deliberate, selection-driven pane instead of a dead tab strip.

## Model decisions (validated)

- **Center = all threads in the active workspace** (machine chat + worklines across
  its projects), never a global list.
- **Every thread has a lead from creation.** Enforced as an invariant (B): thread
  creation defaults the lead. The orchestrator (tertius) refines on top (A) when it
  routes intake, but the invariant never depends on the agent being live.
- **No session-less threads by design.** A thread's "session" is its lead's live
  PTY. Showing it spawns an *idle* process if not attached — tokens burn per turn,
  not per process — so opening the session pane is cheap and never hits an empty
  state.
- **UX split:** thread work → threads; meta/random thoughts → the `tertius ▸` line,
  which reassigns / orchestrates.
- **Keys are Alt-based, never super** (super is Hyprland's). Alt+1..9 = workspace
  jump.

## Section 1 — Workspace-scoped coordination + the lead invariant

- `Channel.machine_threads/1` gains a `workspace_id` filter
  (`where t.workspace_id == ^ws`). The cockpit passes `active_workspace_id(state)`.
  Switching workspace re-scopes the center, not just CREW/footer.
- **A machine root thread per workspace.** `machine_thread/0` → `machine_thread/1`
  (per workspace); `Bootstrap.ensure` guarantees each workspace has exactly one
  open, stage-less machine root (the "general" chat). WS2 gets its own chat card;
  the center is never empty.
- **`tertius ▸` posts to the active workspace's root**, not a global one.
- **Lead invariant:** `Thread.open_changeset` defaults `agent_id` to the workspace's
  designated lead when none is passed — enforced in the one creation path, so it
  holds for human, MCP, and tertius opens alike. "Designated lead" = the workspace's
  first `builder`/coordinator-archetype roster member (deterministic, instant, no
  LLM in the open path). tertius refines afterward.

## Section 2 — The cockpit UX

- **Right session pane** — revive the retired right column. A key toggles it; when
  on it shows the **selected** thread's lead PTY. Move the stack cursor (`j/k`) → the
  pane re-targets that thread's session. Vertical split, session on the right.
- **Spawn-transparent**: an unattached lead PTY spawns/rebinds on toggle (idle =
  zero tokens). No "no session" state — the lead invariant guarantees one exists.
- **Focus**: reuse the `Ctrl+Space` TERM↔NAV machine verbatim. NAV drives the stack;
  `Ctrl+Space` drops focus into the PTY; `H/L` moves between stack and pane. No new
  input model.
- **The top window strip retires.** Redundant now — you navigate sessions by
  navigating threads, and CREW already shows who's live. Resolves the "dead tabs"
  complaint; folds into Slice 5's leaf/leader retirement.
- **CREW becomes the coworker surface (staged, C):** now — seed a richer default
  roster (`reviewer` + `planner` added to the workspace template) so a fresh
  workspace shows a real crew and lead-assignment / reviewer-on-review-stage have
  something to work with. Later — per-coworker verbs in CREW (add/edit/remove/staff),
  mirroring the workspace right-click menu.

## Section 3 — Build order (each TDD, each leaves suites green)

1. **Per-workspace machine root + scoped `machine_threads`** (server).
   `machine_thread/1`; `Bootstrap.ensure` guarantees one root per workspace;
   `machine_threads/2` filters by `workspace_id`. Tests: two workspaces → disjoint
   thread sets; a fresh workspace gets exactly one root.
2. **Lead invariant** (server). `open_changeset` defaults `agent_id` to the
   workspace's designated lead. Tests: no-lead open → lead set; explicit lead
   honored; default resolves from roster.
3. **Cockpit re-scope** (console). Pass `active_workspace_id`; `tertius ▸` posts to
   the active root. Test: switching `active_key` changes `stack_blocks`; composer
   targets the active root.
4. **Retire the top window strip** (console). Remove `Panel.WindowBar` from the
   layout + its `window_tabs`/`select_tab` wiring. Test: layout no longer places the
   strip; no orphaned `select_tab` path.
5. **Toggleable right session pane** (console). Revive the right column as a
   `Panel.Terminal` bound to the selected thread's lead PTY; Alt-chord toggle;
   `H/L` focus; spawn-transparent. Tests: toggle adds/removes the placement; cursor
   move re-targets; focus routing. Live PTY render/routing = Andrew's kitty pass.
6. **Richer default roster** (console). Add `reviewer` + `planner` to the workspace
   template. Test: a templated workspace's roster includes them.

**Gates:** both module suites green after each task; the machine gate
(`flake:check` / `home:switch`) before done — module suites alone are not the gate
for this repo.

## Deferred / follow-ups (YAGNI for this slice)

- New-project / new-workspace creation flow polish (Andrew: "that whole flow needs
  work") — the brief empty-state on add lives here, out of scope for this design.
- CREW per-coworker CRUD verbs (stage 2 of option C).
- Orchestrator-driven smart lead assignment (tertius 4D-5 mandate) refining the
  default lead.
