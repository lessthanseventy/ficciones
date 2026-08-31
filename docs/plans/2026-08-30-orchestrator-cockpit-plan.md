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

**Container hierarchy: Workspace ▸ Project ▸ Thread.** Standard/literal on purpose — "clear beats cute" (the Borges-name-purge lesson). A **Workspace** is a *context* (work, home, a client) holding several **Projects**; a **Project** is a named effort spanning **one or more repos**; **Threads** are the work inside a project.

| Word | Meaning | Replaces / retires |
|---|---|---|
| **Workspace** | A context grouping — a **collection of projects** + a roster + knobs. The Hyprland-style spine down the far left; switch context here. | "world" (already renamed) |
| **Project** | A named effort inside a workspace, spanning **one or more repos**. The SDLC + fuzzy-switch unit (`Ctrl+O`); STACK / the lazygit pane point at its repos (a repo picker when it has several). | new tier (data-model add) |
| **Repo** | A git repo attached to a project (a project has ≥1). Not a hierarchy tier — a project *member*; where worktrees + the lazygit pane live. | (the old workspace "git-tracked folder(s)") |
| **Coworker** | A registered agent identity on the bench (hronir-machine, tertius-machine). Can be staffed to lead. | — |
| **Orchestrator** | The single board-level meta agent (tertius). Routes intake, escalates, runs Maintain. Lives in the command line. | "root meta agent", "god orchestrator", one sense of "leader" |
| **Lead** | The one coworker coordinating one thread. A **manager**: delegates the doing, does not build. | the other sense of "leader" |
| **Thread** | The unit of work/conversation. A **workline** when it carries a non-null SDLC stage; an **untracked thread** for pure exploration. | — |
| **Child thread** | A thread a lead spins off for separable work; own SDLC, reports up. | **"leaf"** (dies entirely) |
| **Crew** | Extra doers staffed *on the same thread* (parallel builders, a reviewer). | — |
| **Ticket** | A **first-class, workspace-scoped issue** (title, body, status, priority, optional label/project/assignee) — a *lightweight terminal ticket tracker*. ("Jira" was used generically, like Kleenex — build the plain thing, **not** the product: no epics/sprints/story-points/workflow ceremony. Closer to GitHub-Issues-light.) 2-second capture (ADHD-friendly): filing does NOT spin up a thread. Funes-native so agents file/read them too (shared backlog for you + the crew). **Promotes** into a thread/workline only when you start working it. **Backend-pluggable** (the repo's `adapters` pattern): `Local` funes table is the default; a workspace can point its tickets at an external backend (**Jira**, GitHub Issues, Linear, …) — same board, same verbs, adapter underneath. Work (threads/branches/commits) can **reference** a ticket, local id or external key (`PROJ-1234` + url). | — (new entity; distinct from `issue` = a blocker raised *on* a thread) |
| **Note** | Funes-native freeform scratch, scoped global / workspace / project / thread — agent-readable/writable (the reason it's funes, not a text file), flows into the same recall the briefs read. | — |

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

### Substrate — tmux = runtime, funes = knowledge

Two orthogonal substrates the cockpit composes; keeping them distinct is what keeps "god mode" intact.

- **tmux = the runtime.** Where live terminals run. **A workspace IS a tmux session** (already true — coworkers run in `console-workspace-<id>`); `super+1..9` switches session = switches workspace, and tmux gives **persistence for free** (coworkers survive the cockpit restarting — kills a class of staleness/roster-backfill bugs) plus **pin-anything** (any TUI, dev server, shell, external app as a session window). A **Project** is a *data grouping within* the session (funes `project_id`), not a tmux primitive — the switcher filters the session's windows to that project; its repos are paths/worktrees the lazygit pane points at. (Alternative reserved: project=session if projects ever need hard-isolated environments — costs a synthetic spine grouping over sessions.)
- **funes = the knowledge.** Threads, facts, tickets, notes, the board, the attention queue — coordination spanning **all** workspaces. **God mode is a funes query, never a tmux attach:** the cockpit isn't a client stuck in one session — it drives tmux programmatically (`send-keys`/`new-window`/`capture`) and embeds the panes it wants, while the survey/orchestrator read funes across everything. Switching session changes which terminals you *see*; the board always spans everything.
- **Native panel vs. pinned app is therefore a free per-surface choice:** agent-shared + searchable → funes-native panel (notes, tickets, the board); a tool you just want open → pin it as a tmux window. Never an architecture decision.

### Local-first, backend-pluggable (every external surface)

The through-line that lets one tool serve home (all local) and work (plugged into a company's infra): **every external-facing surface is local-first with a pluggable backend adapter.** A native funes-backed mode is the default and always works offline/solo; an adapter (under `modules/adapters`) plugs the same surface into the real external backend when you have one. Instances:

- **Tickets** — `Local` funes tracker ↔ Jira / GitHub Issues / Linear.
- **Reviews / PRs** — a local diff/branch review ↔ a real GitHub/GitLab **PR** (pull it, review with the crew, post comments back). A review is a thread entered at the `review` stage; the target is local or an external PR.
- **Repos** — local worktrees ↔ remote origins (already how git works; the lazygit pane spans both).
- (Later: chat/Slack, CI, etc. — same shape.)

Build the **Local** mode first for each; adapters are follow-on and per-user (they need creds/APIs). The abstraction (a backend behaviour) is designed in from the start so adding an adapter never reshapes the surface.

### The cockpit (lazygit paradigm)

**Two columns, not three.** Today's cockpit has *two* rails (left sidebar + right STACK/MEMORY) plus a center — that redundancy is the "doing too much" and the poor use of space. Collapse to lazygit's shape: **a spine + one panel rail + one main.**

- **Spine (far left, thin) = top-level surfaces**, Hyprland-style, current highlighted, `super+1..9` to jump. Not only workspaces — workspaces (contexts) **plus cross-cutting tools**: `Inbox/Tickets` and `Notes` (like Slack's rail = channels + Activity/Later/Files). Some entries are contexts; some are global tools; some can be pinned external apps (tmux). Switching a workspace re-scopes the rail + terminals; the global tools (Tickets/Notes/board) span all workspaces.
- **The panel rail (one column), top-to-bottom in lazygit's own order:**
  - **top** — the active **Project** + `⚙` config + repo-switch (fuzzy `Ctrl+O`); lazygit's status/recent-repos slot.
  - **`NOW` (staging area)** — what's most important / going on right now = the ATTENTION queue (gates + escalations). lazygit's Files/staging.
  - **`THREADS` (the log)** — the ongoing work, stage-aware. lazygit's Commits/Branches.
  - **CREW · MEMORY** — lower.
- **Main panel (the whole right):** follows the focused selection — a thread → its lead conversation + artifact tabs (intent/spec/plan/review) + terminal; a coworker → profile/activity; an attention item → the gate or blocker; STACK-zoom → lazygit. **The old right rail dies into this** (git/activity/detail all become main-on-focus).
- **`+` / `_`:** screen-mode zoom of the focused panel to half / full. The "home surfaces" are zoom targets: zoom `THREADS` → the **pipeline board**; zoom `NOW` → the **triage inbox**; zoom `STACK` → **lazygit** at the focused project's worktree.
- **Bottom:** the orchestrator command line (`tertius ▸`, doubles as the project/workspace switcher via NL) + a context-sensitive verb bar (`?` for the full menu).
- **CRUD/config everywhere:** create/edit/delete screens for every noun — workspace, project, thread, coworker — reached from the `⚙` at the rail top and per-item verbs. Some exists (register/edit/remove_workspace, open/delete_thread, the `n` new-workspace modal); Project CRUD is new.
- **Twists beyond lazygit:** the main panel is a *live interactive* conversation + PTY (not a read-only diff — the existing `Ctrl+Space` TERM↔NAV focus machine already models this); the bottom line is a *conversation* not a command log; ATTENTION is the async-interrupt channel (lazygit-with-a-doorbell); the THREADS panel carries a stage axis (children/crew nest in the main, not the rail).

---

## Slices

Ordered by dependency + value. Each slice is shippable and gate-green on its own. Slice 0 is bite-sized and executable now; Slices 1–4 carry goal + surfaces + acceptance + opening tasks, and get fully decomposed when reached (this repo's design→slice-plan pattern).

### Slice 0 — Cockpit coherence (0.1 DONE; rest parked into Slice 3)

**Status:** **0.1 landed** (d71e314): thread-tagged leaf windows no longer leak onto the leader strip — `view.ex` `window_tabs/1` rejects by the `thread_id` tag first, `t<id>` name as legacy fallback (`leaf_tab?/1`). Console suite 811/0. The root machine thread was already filtered from the survey (0133baf, `Orbis.without_root/2`).

**PARKED into Slice 3:** 0.2 (hide idle leader lanes) and 0.3 (leaf/leader label sweep). Slice 3 rebuilds the strip + sidebar entirely (thread-driven strip, two-column layout), so a display-filter stopgap now would be thrown away. Decision (2026-08-30, Andrew): park them.

### Slice 1 — The orchestrator command line (tertius + receipts)

**STATUS (in progress):** ✅ the BRAIN landed (8534009): `Console.Orchestrator.Router` (pure NL intent-router, 15 tests) + `Console.Orchestrator` (dispatch/classify/confirm with receipts, 22 DB-booted tests) over the exported `Server` facade/contexts. Safe verbs (post/note/ticket/roster/blocked) dispatch straight; consequential (open/approve) confirm first; approve deferred to Slice 4. ⏳ REMAINING: wire the brain into the cockpit UI — the `tertius ▸` line panel + a global focus key + receipt display (keymap/cockpit/panel).

**Goal:** The always-present `tertius ▸` line: type meta-intent, tertius dispatches over the operator MCP toolset, echoes a receipt, confirms consequential actions. The highest-value new capability (anti-conflation + closes the receipt loop).

**Surfaces:** a new orchestrator agent bound to the root machine thread; `modules/console/lib/aleph/panel/composer.ex` (or a new `orchestrator_line`), `keymap.ex` (a global key to focus the line from any panel), the operator verbs already in `scripts/tlon-cli.sh` + the MCP tools (`post_message`, `bank_fact`, `open_thread`, `advance_stage`, `staff_leaf`, reads).

**Shape:** the line is a thin NL front-end. v1 can be rule/intent-routed (verbs: "tell X …" → post_message to X's thread; "remember …" → bank_fact; "spike/explore/build …" → open_thread at the right stage; **"file a ticket …" → create a Ticket in this workspace's Jira (NOT a thread)**; "note …" → a funes note; "what's blocked / who's free" → read; "approve #N" → advance_stage). v2 hands the turn to the tertius agent for open-ended routing. Every dispatch appends a receipt line (`→ filed #51 in backlog ✓`); consequential verbs (open_thread, advance_stage past a gate, delete) show a confirm affordance first.

**Acceptance:** from any panel, one key focuses the line; a "tell hronir …" posts + wakes and shows `→ posted to #N · woke @hronir ✓`; a "remember …" banks a fact with a receipt; an "approve #N" is gated behind a confirm; nothing dispatches silently. Tests drive the intent-router headlessly.

**Opening tasks:** (1) failing test: intent-router maps `"tell @hronir foo"` → `{:post_message, thread_of(hronir), "foo"}`. (2) implement the router as a pure function over the roster + verb table. (3) receipt-format test. (4) wire the key + panel. (5) confirm-gate for consequential verbs.

### Slice 2 — Workspace ▸ Project ▸ Thread (the container model + CRUD)

**STATUS (in progress):** ✅ data entities landed — `Project` (53b6c6e), `Note` + `Ticket` (84e154d); repos = JSON member of `project` (dodges `Server.Repo` clash). ✅ MCP tools landed (61ec216): `file_ticket`/`list_tickets`/`update_ticket`, `write_note`/`get_notes`, `register_project` — workspace-scoped via the bound thread; end-to-end MCP tests. Server 417, console 811, all green. ⏳ REMAINING: the `thread.workspace_id`→default-project backfill (deferred — timestamp-in-SQL care); console CRUD/config screens (fold into Slice 3). Server SIDE of Slice 2 is done.

**Goal:** Make the three-tier hierarchy real in data *before* the cockpit renders it — a **Project** tier between workspace and thread, **Repos** as project members (a project has ≥1 repo, possibly several), and CRUD/config for every noun. Slice 3's workspace spine + project switcher depend on this.

**Surfaces:** server schema — new `project` (belongs_to workspace; name, knobs), `repo` (belongs_to project; path/url), `ticket` (**workspace-scoped**; title, body, status, priority, labels, optional project_id + assignee; `promoted_thread_id` link; `backend` + `external_key`/`external_url` for adapter-backed ones) behind a **`TicketBackend` behaviour** (`Local` funes impl now; `Jira`/`GitHub` adapters as follow-on, under `modules/adapters`), a per-workspace ticket-backend knob, and a `ticket_ref` on threads (link work → a local/external ticket), and `note` (funes-native scratch; polymorphic scope global/workspace/project/thread) tables + migrations; `thread.workspace_id` → `thread.project_id`; new `Server.Projects` + `Server.Tickets` + `Server.Notes` contexts; MCP tools `register/edit/remove_project`, repo attach/detach, `file_ticket`/`update_ticket`/`list_tickets`/`promote_ticket`, `write_note`/`get_notes`, existing workspace/thread/agent CRUD carried over. Console — project switcher plumbing + `⚙` config/CRUD screens.

**Migration care:** existing threads carry `workspace_id`. Backfill one default Project per workspace (the workspace's current repo folder(s) become that project's repos) and repoint threads at it. Reversible; SQLite child-FK rewrite — same pattern as the world→workspace migration (`20260829120000`).

**Acceptance:** a workspace holds multiple projects; a project holds one or more repos; a thread belongs to a project; register/edit/remove works for workspace, project, thread, coworker (CLI + MCP + a cockpit screen); the migration backfills cleanly and reverses; both suites green.

**Note:** decompose when reached — TDD schema-first, one table + context + tool at a time.

### Slice 3 — The lazygit cockpit (workspace spine + panel rail + main)

**Goal:** Collapse the current three-column cockpit into lazygit's shape — a thin **spine of top-level surfaces** (Hyprland-style, `super+1..9`: workspaces **+** the global `Inbox/Tickets` and `Notes` tools; pinned external apps allowed), one **panel rail** (top: active project + `⚙` config + repo fuzzy-switch `Ctrl+O`; then `NOW`/staging = ATTENTION; then `THREADS`/log; then CREW·MEMORY), one **main** that follows focus. The old right rail (STACK/MEMORY) dies into main-on-focus. `+`/`_` screen-mode zoom. Two boards, distinct: the **Tickets board** (per-workspace, capture→triage→backlog→doing→done; a plain lightweight tracker, no ceremony) and the **SDLC pipeline board** (active worklines intent→…→merged); a ticket *promotes* off the Jira board into the pipeline. Plus a Notes surface. Context verb bar. **Absorbs Slice 0's parked work:** 0.2 → the strip goes thread-driven (one lane per active thread by its lead; idle standing lanes gone); 0.3 → leaf/leader labels retired in the UI. Runs on the **tmux=session substrate** (see Substrate above): switching a workspace switches the tmux session; global tools span all sessions via funes.

**Surfaces:** `cockpit.ex` (three-column → spine+rail+main layout, focus machine, screen-mode state), `keymap.ex` (`super+1..9` workspace jump, `Ctrl+O` project switch, in-rail number-jump, `Tab`, `+`/`_`, verb bar), existing panels re-homed (`triage`→NOW, `overview`/`leaves`→THREADS, `roster`/`crew`→CREW, `memory`, `stack`), a pipeline-board render (THREADS zoomed), the ghostty PTY embed for STACK-zoom.

**STACK-zoom = embedded lazygit.** STACK small = git read-model (branch/commits/files, glanceable, no PTY). `+`-zoom = a **real embedded lazygit** (`lazygit -p <path>` in a ghostty PTY) at the focused thread's worktree (`work/<slug>/`, wired in Slice 4), falling back to the project's repo (a repo picker when the project has several). `_` collapses back. Reuses the `Ctrl+Space` TERM↔NAV leader verbatim (lazygit captures keys like any PTY) — no new input model. Tames worktree sprawl: navigate by thread, git follows focus. **Infra:** add `lazygit` to the flake (system-only today).

**Acceptance:** two columns + spine, no redundant right rail; `super+1..9` switches workspace and re-scopes everything; `Ctrl+O` fuzzy-switches project; NOW/THREADS/CREW/MEMORY stack in the rail; the strip is thread-driven (idle lanes gone); `+`/`_` zoom (THREADS→board, NOW→inbox, STACK→lazygit at the focused worktree); no leaf/leader in labels; main follows focus. Builds on the landed `Ctrl+Space` TERM↔NAV + `h/l/H/L` focus machine.

**Note:** largest slice — decompose when reached. Mine `2026-08-20-tlon-lazygit-panels-design.md` + `2026-08-23-aleph-cockpit-clarity-*.md`, subordinate to the model above.

### Slice 4 — Lead-as-manager + any-stage entry + orchestrator staffing

**Goal:** Make the coordination model real, not just displayed. A lead delegates (staffs crew / spins child threads / assigns a reviewer) rather than building. Threads open at any stage. tertius actually orchestrates intake + escalation (with human gates).

**Surfaces:** server — `staff_leaf`/`spawn_crew`/`open_thread` (tool.ex), the workline stage machine (`advance_stage`, gates), lead assignment (`Channel.assign_lead`), the orchestrator's Maintain loop; console — the lead conversation main panel, gate surfacing into ATTENTION.

**Acceptance:** opening a thread at `review`/`build`/untracked works and owes the right artifacts; a **review** thread targets either a local diff or an external PR (backend-pluggable — see "Local-first" above; local mode now, GitHub/GitLab PR adapter follow-on); a lead, asked to build, delegates to crew/child threads and reports up; tertius routes a new intent to a lead and surfaces the spec/merge gates + escalations into ATTENTION; the two human gates park in `awaiting:andrew`.

**Note:** mine `2026-08-27-ai-native-sdlc-workline-design.md`, `2026-08-22-per-thread-agents-design.md`, `2026-08-19-orbis-tertius-meta-thread-design.md` — subordinate.

### Slice 5 — Nomenclature retirement + doc supersession

**Goal:** Finish the rename in *code* (`leaf`→`thread`/`child_thread`, `leader`→`lead`/`orchestrator`), then supersede the lineage docs.

**Surfaces:** the ~205 `leaf` + ~193 `leader` identifiers across `modules/server` + `modules/console`; module/function/var/test names; the `@leaf_window`/`leaf_window?` seam retired. Then move superseded docs under a `docs/plans/superseded/` (or stamp a header) and update `docs/plans` index.

**Acceptance:** `grep -rin '\bleaf\b\|\bleader\b' modules/{server,console}/lib` returns only intentional survivors (if any, documented); both suites green; lineage docs marked superseded by this plan.

---

## Execution notes

- **Execution:** autonomous (2026-08-30 — Andrew: "let you cook … won't try it until we're done … do whatever"). Order at builder's discretion in dependency order; verify by tests + gates (Andrew is not eye-passing between slices), commit small, report progress.
- **Order:** 0 → 1 → 2 → 3 → 4 → 5. **Slice 0** — 0.1 done, rest parked into 3. **Slice 1** — orchestrator command line (highest new value, lives in the current cockpit). **Slice 2** — the Workspace▸Project▸Thread data model + CRUD (prereq for the spine/switcher). **Slice 3** — the big UX reshape (two-column lazygit cockpit; absorbs 0.2/0.3). **Slice 4** — makes the coordination model real (lead-as-manager, any-stage, orchestrator staffing, per-thread worktrees). **Slice 5** — cleans the language and archives lineage.
- **Discipline:** TDD every task (RED → GREEN → REFACTOR), commit small, run both module suites + the machine gate (`flake:check` / `home:switch`) before calling a slice green — module unit suites alone are NOT the gate for this repo.
- **Dogfood:** each slice should be usable live in the running cockpit before the next starts.
