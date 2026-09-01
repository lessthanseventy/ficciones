# Lead-as-manager coordination model (Slice 4D)

**Date:** 2026-08-31
**Status:** design, validated. Subordinate to `2026-08-30-orchestrator-cockpit-plan.md` (Slice 4);
mines `2026-08-27-ai-native-sdlc-workline-design.md`, `2026-08-22-per-thread-agents-design.md`,
`2026-08-19-orbis-tertius-meta-thread-design.md`.

Slice 4's 4A (`Server.Worktree`), 4B (`Server.repo_for_thread`), 4C (console lazygit zoom) are done.
This doc is **4D — making the coordination model real**.

## The model

The orchestrator is **tertius-as-coworker**, not new machinery. tertius already lives as a coworker on
the machine root thread; an intent posted there already wakes it. 4D makes its *role* "orchestrator":
given a manager's mandate + toolset, it opens a work thread, picks a lead from the roster, assigns +
briefs it, and stays out of the building.

A **lead** delegates through the same shape of tools:
- **Child threads** for substantial sub-efforts — each a real work-atom with its own lead, linked to
  its parent, reporting up when it closes.
- **Crew** for bounded in-thread tasks (review a diff, run a check) — ephemeral workers that report
  back into the same thread (the reviewer is today's only role; roles grow with real demand).

**The split that keeps this buildable:** we build and test the *substrate* — the schema link, any-stage
entry, the delegation MCP tools, the report-up wake, the ATTENTION surfacing. The *judgment* (which
lead, when to delegate, build vs. staff) is LLM behavior, delivered as a mandate/brief and verified
live — not unit-tested.

### In scope
Any-stage entry; `parent_thread_id` + report-on-close; the lead/orchestrator toolset (open child with
parent+stage+lead, first-class `assign_lead`, crew beyond reviewer as needed); gates/escalations into
the NOW/ATTENTION pane; the tertius orchestrator mandate.

### Deferred (YAGNI)
External PR review backends (GitHub/GitLab) — local-diff review only now, per the plan's local-first.
Capability/load-based auto-staffing heuristics — tertius uses judgment, no scoring engine. Crew role
explosion — add roles only as concrete tasks demand.

## Data model

Two additive changes, both following the `project_id` precedent (nullable `ALTER TABLE ADD COLUMN`,
reversible; SQLite pattern at `20260830120100`).

- **`thread.parent_thread_id`** — nullable self-referential FK (`belongs_to :parent, Server.Thread`).
  Set when a lead opens a child; nil for top-level threads. Makes lineage queryable (stack renders a
  child under its parent) and gives report-up a target. **Unlink, not cascade** — deleting a parent
  unlinks children (matching how `delete_thread` unlinks facts/issues), never orphan-deletes them. A
  thread can't be its own parent; the FK enforces the parent exists.

- **Any-stage entry** — `Workline.open/1` gains an optional `:stage` (default `"intent"`), validated
  ∈ `@stages` minus terminal `"merged"`. Opening *at* `build` does not retroactively demand
  `intent.md`/`spec.md`; it sets the starting position, and *advances from there* owe their artifacts.
  The opening brief is that stage's brief (`Brief.stage_message`). "Untracked" entry is a plain
  `open_thread` (already exists). Operator-initiated later-stage opens don't gate; only the existing
  machine-born-intent gate stays.

## The toolset (MCP)

Identity is connection-bound (a tool knows the calling thread/agent), which shapes the design:
**opening a child infers its parent from the caller; acting on another thread takes an explicit
`thread_id`.**

- **`StaffChild`** (extend today's `StaffLeaf`; renamed in Slice 5) — the primary delegation verb.
  Opens a child work thread with `parent_thread_id` = caller's thread (inferred), inheriting the
  parent's `project_id`, taking `title`, optional `stage` (any-stage), and a `lead` handle. Resolves
  the agent, opens, assigns, posts the opening brief. One call: "spin a child to do X, led by @menard,
  entering at build."
- **`AssignLead`** (new, first-class) — `(thread_id, handle)`: (re)assign a lead on an *existing*
  thread. tertius's staffing verb at intake or reassignment. Explicit `thread_id` because the
  orchestrator acts on threads other than its own — the one departure from connection-bound. Today
  `assign_lead` is only reachable inside `StaffLeaf`; promoting it lets tertius staff without
  re-opening.
- **`SpawnCrew`** (exists) — bounded in-thread worker (reviewer today). Roles grow with demand.
- **Unchanged & reused:** `AdvanceStage`, `SubmitReview`, `CloseThread`, `OpenThread`.

## Report-up, gates, ATTENTION

- **Report-up on close.** `Channel.close_thread/1` (and the workline merge that ends a thread) is the
  single hook: if the closing thread has a `parent_thread_id`, funes posts a system report into the
  parent thread — `✅ child #N "<title>" — <outcome>` — that `@mentions` the parent's lead. No new
  wake machinery: the existing `Aleph.Mention` Bus router wakes a mentioned coworker. A child may also
  `@mention` the parent lead mid-flight for interim updates (works today).
- **Gates into ATTENTION.** Parking already broadcasts `:workline_gated` + sets `awaiting: "andrew"`,
  and `workline_statuses/0` exposes every awaiting thread — the NOW/ATTENTION rail pane renders those
  as an actionable list. Mostly wiring an existing read into the pane.
- **Wire the approve verb.** The tertius `approve N` verb is already y/n-gated (Task 1) but its confirm
  returns a stub *("wired in Slice 4")*. This slice: `Orchestrator.confirm({:approve, n}, ctx)` →
  `Workline.approve(thread)`, advancing a gated stage. The two human gates become a one-keypress
  approve from the cockpit.
- **Escalation.** A blocked lead raises it by existing means (`RaiseIssue`, or setting `awaiting`),
  landing in the same NOW list as gates. "A lead is stuck" and "a gate needs andrew" are one surface.

## tertius's mandate

The one genuinely-LLM piece. tertius's role becomes "orchestrator": its mandate/brief says triage
intents that land on the machine root thread, open a work thread, pick + assign a lead, surface gates,
**do not build.** Ships as its profile mandate + brief text; tuned live. The substrate makes the
mandate *possible*; the mandate makes tertius *use* it well.

## Testing strategy

- **Unit-tested (server):** `parent_thread_id` migration + changeset; any-stage `Workline.open`;
  `StaffChild`/`AssignLead` composition; report-up (a child close posts to its parent + resolves the
  parent lead); `approve` → `Workline.approve` and `Orchestrator.confirm({:approve, …})`.
- **Console:** the NOW pane renders `workline_statuses` gates.
- **Live (Andrew):** tertius triaging/staffing sensibly, leads delegating vs building, the loop
  *feeling* right. Briefed, not asserted.

## Build order (TDD each; report between)

1. ✅ **4D-1** any-stage entry — server-only, self-contained. **DONE** (server 451/0).
2. ✅ **4D-2** `parent_thread_id` (migration + changeset + `open_thread` sets it) + report-up on close. **DONE**.
3. ✅ **4D-3** toolset — `StaffLeaf` now parents the child + first-class `assign_lead`. **DONE**.
4. ✅ **4D-4** wire `open`→`open_workline` / `approve`→`approve_workline` + NOW/ATTENTION gate surfacing. **DONE** (console 879/5-sandbox).
5. ⏳ **4D-5** tertius orchestrator mandate/brief (config; **live-tuned** — the LLM-behavior piece, Andrew's step).

## Status (2026-08-31)

Substrate 4D-1…4D-4 built + green, TDD throughout. Uncommitted (local-iteration norm). Remaining:
4D-5 (tertius's mandate — a prompt, iterated live), the machine gate (`flake:check`/`home:switch`)
before calling the whole slice green, and Andrew's live cockpit passes (4C lazygit + the coordination
loop). Naming (`leaf`→`child`) is Slice 5.
