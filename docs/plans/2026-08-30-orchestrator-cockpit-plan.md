# Orchestrator Cockpit — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reshape Tlön's coordination model and cockpit so the human works at *manager altitude* — talking to an orchestrator and per-thread leads, never micromanaging doers — over a lazygit-style panel UI, with a nomenclature that finally matches the model.

**Architecture:** Three tiers of coordination — a board-level **orchestrator** (tertius), a per-thread **lead** (a manager who delegates, never builds), and **doers** (crew / child threads) that only surface when a manager escalates them. The cockpit is a lazygit paradigm: numbered single-purpose list panels, a main panel that follows the focused selection, `+`/`_` screen-mode zoom, and a context verb bar. An always-present **orchestrator command line** routes natural-language meta-intent over the operator MCP toolset and echoes a receipt for every dispatch.

**Tech Stack:** Elixir (server = funes channel/MCP; console = raxol TUI cockpit), tmux + ghostty embedded terminals, the funes MCP tool surface, SQLite.

**Status source of truth:** This doc reflects the 2026-08-30 design conversation and is authoritative. The lineage docs below are older and *subordinate* — mined for detail, not treated as co-equal.

**Lineage (staler, subordinate):** `2026-08-22-per-thread-agents-design.md` (leaves / leader-of-leaders), `2026-08-19-orbis-tertius-meta-thread-design.md` (the meta agent / orchestrator), `2026-08-20-tlon-lazygit-panels-design.md` (panel rework), `2026-08-27-ai-native-sdlc-workline-design.md` (stage machine, roles, gates), `2026-08-27-clarity-rename-slack-shape-design.md` (kill "leaf", one noun = thread), `2026-08-20-tlon-long-term-vision.md` (munder-difflin comparison, god orchestrator). When this plan and a lineage doc disagree, this plan wins.

---

## The model (authoritative)

### Vocabulary — what each word means, and what dies

| Word | Meaning | Replaces / retires |
|---|---|---|
| **Coworker** | A registered agent identity on the bench (hronir-machine, tertius-machine). Can be staffed to lead. | — |
| **Orchestrator** | The single board-level meta agent (tertius). Routes intake, escalates, runs Maintain. Lives in the command line. | "root meta agent", "god orchestrator", one sense of "leader" |
| **Lead** | The one coworker coordinating one thread. A **manager**: delegates the doing, does not build. | the other sense of "leader" |
| **Thread** | The unit of work/conversation. A **workline** when it carries a non-null SDLC stage; an **untracked thread** for pure exploration. | — |
| **Child thread** | A thread a lead spins off for separable work; own SDLC, reports up. | **"leaf"** (dies entirely) |
| **Crew** | Extra doers staffed *on the same thread* (parallel builders, a reviewer). | — |

**Retire `leaf` and `leader` from code and UI.** `leaf` → `thread` / `child thread`; `leader` → `lead` (per-thread) or `orchestrator` (board). ~205 `leaf` + ~193 `leader` references today (Slice 4).

### The three tiers

```
ORCHESTRATOR (tertius, one, board-level)  ── command line
  routes intake · escalates stuck threads · runs Maintain
  │
  ├── THREAD = workline    lead: a manager coworker
  │     intent → spec → plan → build → verify → review → merged   (enter at ANY stage)
  │     • the LEAD delegates: staffs crew / spins child threads / assigns a reviewer
  │     • the LEAD never builds — it coordinates and reports up
  │     • CREW = doers on this thread   · CHILD THREAD = separable sub-workline
  │
  └── THREAD …
```

### Interaction laws

1. **You always talk to a manager.** Orchestrator in the command line, or a lead in the main panel. Doers never surface unless a manager escalates them up.
2. **Enter at any stage.** "review this PR" opens at `review`; "spike X" opens at `build` (untracked/throwaway); "explore Y" is an untracked thread with no stage; "build X properly" opens at `intent`. The lead adapts to the entry point.
3. **Automatic in the middle, you at the ends + exceptions.** Auto: routing, safe mid-stage transitions, spawning crew, verify, kicking off review, Maintain monitors. Surfaced to you (the **attention queue**): the two judgment gates (approve-before-build, approve-the-merge) plus escalations (blocked lead, failing test, unroutable intent, machine-born intent wanting a green light).
4. **The orchestrator line shows receipts.** Every dispatch echoes what it did (`→ posted to #2 · woke @hronir ✓`; `→ banked fact #47 ✓`). Consequential dispatches (kick off work, approve a merge, delete anything) confirm before firing. A command line you talk *into* with no confirmation is the exact failure this repo hit on 2026-08-30 (a reply lost to a terminal) — it must never be write-only.

### The cockpit (lazygit paradigm)

- **Left rail:** numbered single-purpose list panels — `1 ATTENTION` (needs-you) · `2 THREADS` (worklines, stage-aware) · `3 CREW` (the bench) · `4 MEMORY` · `5 STACK` (git). Number-jump, `Tab` cycles.
- **Main panel:** follows the focused selection. A thread → its lead conversation + artifact tabs (intent/spec/plan/review) + terminal. A coworker → profile/activity. An attention item → the gate or blocker.
- **`+` / `_`:** screen-mode zoom of the focused panel to half / full. The three "home surfaces" are just zoom targets: zoom `2 THREADS` → the **pipeline board**; zoom `1 ATTENTION` → the **triage inbox**; the **chief-of-staff chat** is the always-present command line, not a screen.
- **Bottom:** the orchestrator command line (`tertius ▸`) + a context-sensitive verb bar (`?` for the full menu).
- **Twists beyond lazygit:** the main panel is a *live interactive* conversation + PTY (not a read-only diff — the existing `Ctrl+Space` TERM↔NAV focus machine already models this); the bottom line is a *conversation* not a command log; ATTENTION is the async-interrupt channel (lazygit-with-a-doorbell); the THREADS panel carries a stage axis (children/crew nest in the main, not the rail).

---

## Slices

Ordered by dependency + value. Each slice is shippable and gate-green on its own. Slice 0 is bite-sized and executable now; Slices 1–4 carry goal + surfaces + acceptance + opening tasks, and get fully decomposed when reached (this repo's design→slice-plan pattern).

### Slice 0 — Cockpit coherence (execute now)

**Goal:** Stop the current cockpit from lying. Leaves off the leader strip; idle standing coworkers off the strip; (root already off the survey). A display-filter stopgap the Slice 2 reshape supersedes — but it makes *today's* screen honest.

**Surfaces:** `modules/console/lib/aleph/view.ex` (`window_tabs/1`, the strip's `@leaf_window` reject at ~L485–499), `modules/console/lib/aleph/cockpit.ex` (`parse_tlon_tabs`/`leaf_window?` at ~L2312, which already stamp `thread_id` from the `@funes_thread` tag), tests in `modules/console/test/aleph/view_test.exs`.

**Context the engineer needs:** The strip is built by `window_tabs/1`. It rejects leaf windows by *name* regex `^t\d+$` — but leaves are now named descriptively (e.g. `builder-hola-who-is-this-what`) and carry a `@funes_thread` tag (parsed into the tab's `thread_id`). So the name-only reject misses them and they leak onto the strip. A "leader lane" is a window with no `thread_id`. An idle lane is one whose agent is neither warm nor leading an open thread.

**Task 0.1 — Reject leaf windows by their thread_id tag, not just the name**

**Step 1: Write the failing test** in `view_test.exs`: a tab with `thread_id: 2` (any name) is excluded from `window_tabs`; a leader tab (`thread_id: nil`, name `hronir`) is kept; a legacy `t7`-named tab is still excluded.

**Step 2: Run it** — `mix test test/aleph/view_test.exs -v` — expect FAIL (builder-named leaf currently kept).

**Step 3: Implement** — in `view.ex` change the reject to catch either shape:
```elixir
|> Enum.reject(fn t -> leaf_tab?(t) end)
# where:
defp leaf_tab?(%{thread_id: tid}) when is_integer(tid), do: true
defp leaf_tab?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)
```
(Keep the regex as the legacy fallback; the `thread_id` clause is the real rule. Reuse `Cockpit.leaf_window?/1` if it's already exported for the same shape — DRY.)

**Step 4: Run** — expect PASS.

**Step 5: Commit** — `fix(strip): keep thread-tagged leaf windows off the leader strip`.

**Task 0.2 — Hide idle leader lanes (show only warm-or-leading coworkers)**

**Step 1: Write the failing test:** given tabs `[hronir(warm), tertius(cold, leads nothing)]`, `window_tabs` returns only `hronir`; a cold coworker that *leads an open thread* is kept.

**Step 2: Run** — expect FAIL (tertius kept today).

**Step 3: Implement** — after presence-join, reject a leader tab whose agent is `nil`-warm AND not present in the set of leads of open threads. Source the leading-agents set from `reads` (already carries roster; add the open-thread leads from `Channel.staffed_machine_threads/0` if not already in `reads`, threaded through `data_for/2` so `window_tabs` stays a pure render — no server read in the panel).

**Step 4: Run** — expect PASS.

**Step 5: Commit** — `feat(strip): show only working coworker lanes (idle lanes → CREW panel)`.

**Task 0.3 — User-facing label sweep (leaf/leader → thread/lead), labels only**

Rename only the *visible strings* and section titles (LEAVES → CHILD THREADS or nest them; "leader" labels → "lead"), not the code identifiers (that's Slice 4). Grep `modules/console/lib/aleph/panel/*.ex` for user-facing `"Leaf"`/`"Leader"`/`"LEAVES"` literals. TDD each panel's render test. Commit per panel.

**Acceptance:** the running cockpit shows exactly the standing lanes that are working; leaves live under the Leaves/Child-threads panel; no "leaf"/"leader" in visible labels; both suites green.

### Slice 1 — The orchestrator command line (tertius + receipts)

**Goal:** The always-present `tertius ▸` line: type meta-intent, tertius dispatches over the operator MCP toolset, echoes a receipt, confirms consequential actions. The highest-value new capability (anti-conflation + closes the receipt loop).

**Surfaces:** a new orchestrator agent bound to the root machine thread; `modules/console/lib/aleph/panel/composer.ex` (or a new `orchestrator_line`), `keymap.ex` (a global key to focus the line from any panel), the operator verbs already in `scripts/tlon-cli.sh` + the MCP tools (`post_message`, `bank_fact`, `open_thread`, `advance_stage`, `staff_leaf`, reads).

**Shape:** the line is a thin NL front-end. v1 can be rule/intent-routed (verbs: "tell X …" → post_message to X's thread; "remember …" → bank_fact; "spike/explore/build …" → open_thread at the right stage; "what's blocked / who's free" → read; "approve #N" → advance_stage). v2 hands the turn to the tertius agent for open-ended routing. Every dispatch appends a receipt line; consequential verbs (open_thread, advance_stage past a gate, delete) show a confirm affordance first.

**Acceptance:** from any panel, one key focuses the line; a "tell hronir …" posts + wakes and shows `→ posted to #N · woke @hronir ✓`; a "remember …" banks a fact with a receipt; an "approve #N" is gated behind a confirm; nothing dispatches silently. Tests drive the intent-router headlessly.

**Opening tasks:** (1) failing test: intent-router maps `"tell @hronir foo"` → `{:post_message, thread_of(hronir), "foo"}`. (2) implement the router as a pure function over the roster + verb table. (3) receipt-format test. (4) wire the key + panel. (5) confirm-gate for consequential verbs.

### Slice 2 — The lazygit cockpit (panels + zoom + verb bar)

**Goal:** Reshape the cockpit into the lazygit paradigm: numbered rail (`1 ATTENTION · 2 THREADS · 3 CREW · 4 MEMORY · 5 STACK`), follow-the-focus main, `+`/`_` screen-mode zoom, context verb bar. The strip becomes **thread-driven** (one lane per active thread, labeled by its lead) — superseding Slice 0's display-filter stopgap. The three home surfaces become zoom targets.

**Surfaces:** `cockpit.ex` (layout, focus machine, screen-mode state), `keymap.ex` (number-jump, `Tab`, `+`/`_`, verb bar), the existing panels (`triage`→ATTENTION, `overview`/`leaves`→THREADS, `roster`/`crew`→CREW, `memory`, `stack`), a new pipeline-board render (THREADS zoomed), the ghostty PTY embed (already used for the center terminal) for STACK's zoom.

**STACK-zoom = embedded lazygit.** STACK small = today's git read-model (branch/commits/files, glanceable, no PTY). `+`-zoom = a **real embedded lazygit** in a ghostty PTY, `lazygit -p <path>` pointed at the focused context's worktree — the focused thread's `work/<slug>/` (once Slice 3 wires per-thread worktrees), falling back to the focused workspace's repo root. `_` collapses back to the glance. Reuses the existing `Ctrl+Space` TERM↔NAV leader verbatim (lazygit captures keys like any PTY; the leader escapes back to nav) — no new input model. This tames worktree sprawl: navigate by thread, git context follows focus. **Infra:** add `lazygit` to the flake (currently system-only) so the cockpit's dependency is nix-owned.

**Acceptance:** number keys jump panels; `+`/`_` zoom the focused panel to half/full; zoom THREADS → pipeline board across stages; zoom ATTENTION → triage inbox; zoom STACK → live lazygit at the focused worktree (repo root until Slice 3); the verb bar shows only the focused panel's keys; the main follows the focused selection. Builds on the already-landed Phase 0/1 focus machine (`Ctrl+Space` TERM↔NAV, `h/l/H/L`).

**Note:** decompose fully when reached — this is the largest slice. Mine `2026-08-20-tlon-lazygit-panels-design.md` and `2026-08-23-aleph-cockpit-clarity-*.md` for the panel detail, subordinate to the model above.

### Slice 3 — Lead-as-manager + any-stage entry + orchestrator staffing

**Goal:** Make the coordination model real, not just displayed. A lead delegates (staffs crew / spins child threads / assigns a reviewer) rather than building. Threads open at any stage. tertius actually orchestrates intake + escalation (with human gates).

**Surfaces:** server — `staff_leaf`/`spawn_crew`/`open_thread` (tool.ex), the workline stage machine (`advance_stage`, gates), lead assignment (`Channel.assign_lead`), the orchestrator's Maintain loop; console — the lead conversation main panel, gate surfacing into ATTENTION.

**Acceptance:** opening a thread at `review`/`build`/untracked works and owes the right artifacts; a lead, asked to build, delegates to crew/child threads and reports up; tertius routes a new intent to a lead and surfaces the spec/merge gates + escalations into ATTENTION; the two human gates park in `awaiting:andrew`.

**Note:** mine `2026-08-27-ai-native-sdlc-workline-design.md`, `2026-08-22-per-thread-agents-design.md`, `2026-08-19-orbis-tertius-meta-thread-design.md` — subordinate.

### Slice 4 — Nomenclature retirement + doc supersession

**Goal:** Finish the rename in *code* (`leaf`→`thread`/`child_thread`, `leader`→`lead`/`orchestrator`), then supersede the lineage docs.

**Surfaces:** the ~205 `leaf` + ~193 `leader` identifiers across `modules/server` + `modules/console`; module/function/var/test names; the `@leaf_window`/`leaf_window?` seam retired. Then move superseded docs under a `docs/plans/superseded/` (or stamp a header) and update `docs/plans` index.

**Acceptance:** `grep -rin '\bleaf\b\|\bleader\b' modules/{server,console}/lib` returns only intentional survivors (if any, documented); both suites green; lineage docs marked superseded by this plan.

---

## Execution notes

- **Order:** 0 → 1 → 2 → 3 → 4. Slice 0 now (relief); Slice 1 next (highest new value, lives in the current cockpit); Slice 2 is the big UX reshape; Slice 3 makes the model real; Slice 4 cleans the language and archives lineage.
- **Discipline:** TDD every task (RED → GREEN → REFACTOR), commit small, run both module suites + the machine gate (`flake:check` / `home:switch`) before calling a slice green — module unit suites alone are NOT the gate for this repo.
- **Dogfood:** each slice should be usable live in the running cockpit before the next starts.
