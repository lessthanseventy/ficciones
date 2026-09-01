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
- **Center = a vertical stack of foldable Slack-style thread cards** (2026-08-30 refinement — this is the heart, not a "follow-focus detail panel"). Each card: **folded** → a one-line header (title · lead · stage/gate), so a stack of folded cards IS the thread list; **unfolded** (`z`, the fold/unfold zoom) → the full conversation + artifacts **and its own reply input**. Folding replaces the list-vs-detail split — one stack, compress what you're not reading, expand what you are. **Default fold: the most-recently-active thread unfolded, the rest folded.** The old right rail (STACK/MEMORY) dies — those become left-rail panels.
- **Inputs are per-thread + one meta:** each unfolded card has its own `‹reply to #N…›`; the **permanent `tertius ▸` meta input sits at the very bottom, always** (the orchestrator line — replaces the `:` stopgap; also the project/workspace switcher via NL). Focus is the existing NAV↔type toggle, now over many inputs: `j/k` move the stack, `z` folds, focusing a card's input (or the meta input) types.
- **`+` / `_` / `z`:** fold/unfold a thread card (`z` toggles the focused card; `+`/`_` can still full-screen a rail panel — board/inbox/lazygit — when one is focused). STACK-zoom → **lazygit** at the focused project's worktree.
- **Verb bar** (`?` for the full menu) below the meta input.
- **CRUD/config everywhere:** create/edit/delete screens for every noun — workspace, project, thread, coworker — reached from the `⚙` at the rail top and per-item verbs. Some exists (register/edit/remove_workspace, open/delete_thread, the `n` new-workspace modal); Project CRUD is new.
- **Twists beyond lazygit:** the main panel is a *live interactive* conversation + PTY (not a read-only diff — the existing `Ctrl+Space` TERM↔NAV focus machine already models this); the bottom line is a *conversation* not a command log; ATTENTION is the async-interrupt channel (lazygit-with-a-doorbell); the THREADS panel carries a stage axis (children/crew nest in the main, not the rail).

---

## Slices

Ordered by dependency + value. Each slice is shippable and gate-green on its own. Slice 0 is bite-sized and executable now; Slices 1–4 carry goal + surfaces + acceptance + opening tasks, and get fully decomposed when reached (this repo's design→slice-plan pattern).

### Slice 0 — Cockpit coherence (0.1 DONE; rest parked into Slice 3)

**Status:** **0.1 landed** (d71e314): thread-tagged leaf windows no longer leak onto the leader strip — `view.ex` `window_tabs/1` rejects by the `thread_id` tag first, `t<id>` name as legacy fallback (`leaf_tab?/1`). Console suite 811/0. The root machine thread was already filtered from the survey (0133baf, `Orbis.without_root/2`).

**PARKED into Slice 3:** 0.2 (hide idle leader lanes) and 0.3 (leaf/leader label sweep). Slice 3 rebuilds the strip + sidebar entirely (thread-driven strip, two-column layout), so a display-filter stopgap now would be thrown away. Decision (2026-08-30, Andrew): park them.

### Slice 1 — The orchestrator command line (tertius + receipts)

**STATUS — v1 DONE (functional).** ✅ BRAIN (8534009): `Console.Orchestrator.Router` (pure NL router, 15 tests) + `Console.Orchestrator` (dispatch/classify/confirm + receipts, 22 DB-booted tests) over the exported `Server` facade. ✅ UI (d40552d): `:` opens a `TERTIUS ▸` prompt from any panel (`:orchestrate` input mode); Enter → route → dispatch → receipt flash; StatusBar renders the prompt. Safe verbs fire; consequential SHOW-without-firing. ⏳ DEFERRED: the interactive y/n confirm for consequential verbs (→ Slice 3 reshape); `approve` execution (→ Slice 4 workline machine); v2 hand-open-ended-chat-to-the-tertius-agent (future).

**Goal:** The always-present `tertius ▸` line: type meta-intent, tertius dispatches over the operator MCP toolset, echoes a receipt, confirms consequential actions. The highest-value new capability (anti-conflation + closes the receipt loop).

**Surfaces:** a new orchestrator agent bound to the root machine thread; `modules/console/lib/aleph/panel/composer.ex` (or a new `orchestrator_line`), `keymap.ex` (a global key to focus the line from any panel), the operator verbs already in `scripts/tlon-cli.sh` + the MCP tools (`post_message`, `bank_fact`, `open_thread`, `advance_stage`, `staff_leaf`, reads).

**Shape:** the line is a thin NL front-end. v1 can be rule/intent-routed (verbs: "tell X …" → post_message to X's thread; "remember …" → bank_fact; "spike/explore/build …" → open_thread at the right stage; **"file a ticket …" → create a Ticket in this workspace's Jira (NOT a thread)**; "note …" → a funes note; "what's blocked / who's free" → read; "approve #N" → advance_stage). v2 hands the turn to the tertius agent for open-ended routing. Every dispatch appends a receipt line (`→ filed #51 in backlog ✓`); consequential verbs (open_thread, advance_stage past a gate, delete) show a confirm affordance first.

**Acceptance:** from any panel, one key focuses the line; a "tell hronir …" posts + wakes and shows `→ posted to #N · woke @hronir ✓`; a "remember …" banks a fact with a receipt; an "approve #N" is gated behind a confirm; nothing dispatches silently. Tests drive the intent-router headlessly.

**Opening tasks:** (1) failing test: intent-router maps `"tell @hronir foo"` → `{:post_message, thread_of(hronir), "foo"}`. (2) implement the router as a pure function over the roster + verb table. (3) receipt-format test. (4) wire the key + panel. (5) confirm-gate for consequential verbs.

### Slice 2 — Workspace ▸ Project ▸ Thread (the container model + CRUD)

**STATUS — DONE.** ✅ data entities (53b6c6e Project, 84e154d Note+Ticket; repos = JSON member of `project`). ✅ MCP tools (61ec216: file_ticket/list_tickets/update_ticket/write_note/get_notes/register_project, e2e-tested). ✅ backfill (dac5785: `Bootstrap.ensure` gives every workspace a `general` project + repoints nil-project threads, idempotent, changeset timestamps). Server 421, console 840, green. (Console CRUD/config *screens* fold into Slice 3's cockpit build.)

**Goal:** Make the three-tier hierarchy real in data *before* the cockpit renders it — a **Project** tier between workspace and thread, **Repos** as project members (a project has ≥1 repo, possibly several), and CRUD/config for every noun. Slice 3's workspace spine + project switcher depend on this.

**Surfaces:** server schema — new `project` (belongs_to workspace; name, knobs), `repo` (belongs_to project; path/url), `ticket` (**workspace-scoped**; title, body, status, priority, labels, optional project_id + assignee; `promoted_thread_id` link; `backend` + `external_key`/`external_url` for adapter-backed ones) behind a **`TicketBackend` behaviour** (`Local` funes impl now; `Jira`/`GitHub` adapters as follow-on, under `modules/adapters`), a per-workspace ticket-backend knob, and a `ticket_ref` on threads (link work → a local/external ticket), and `note` (funes-native scratch; polymorphic scope global/workspace/project/thread) tables + migrations; `thread.workspace_id` → `thread.project_id`; new `Server.Projects` + `Server.Tickets` + `Server.Notes` contexts; MCP tools `register/edit/remove_project`, repo attach/detach, `file_ticket`/`update_ticket`/`list_tickets`/`promote_ticket`, `write_note`/`get_notes`, existing workspace/thread/agent CRUD carried over. Console — project switcher plumbing + `⚙` config/CRUD screens.

**Migration care:** existing threads carry `workspace_id`. Backfill one default Project per workspace (the workspace's current repo folder(s) become that project's repos) and repoint threads at it. Reversible; SQLite child-FK rewrite — same pattern as the world→workspace migration (`20260829120000`).

**Acceptance:** a workspace holds multiple projects; a project holds one or more repos; a thread belongs to a project; register/edit/remove works for workspace, project, thread, coworker (CLI + MCP + a cockpit screen); the migration backfills cleanly and reverses; both suites green.

**Note:** decompose when reached — TDD schema-first, one table + context + tool at a time.

### Slice 3 — The cockpit reshape (spine · rail · center thread-stack · meta input)

**STATUS (in progress — heavily live-iterated with Andrew via console:run + hot-reload):**
✅ **Center thread stack**: `Panel.ThreadStack` (foldable Slack cards, styled — accent gutter on the active card, nested author-coloured wrapped messages, `↳ reply` affordance, breathing room; a32a480). Sources `Channel.machine_threads()` (NOT project chorus — that was the "no threads yet" bug, 1c01e8d). Default center (no `v` needed).
✅ **Keyboard nav (standard)**: `j/k/↑↓` move · `g/G` top/bottom · `z/Space` fold · `Z/+` zoom · active card highlighted, cursor persists. CRITICAL FIX (57325dc): a workspace routes keys through `handle_tlon`, which forwards everything to the terminal while `focus.in_terminal?` — stack keys had to be added THERE (gated on `center_view: :chat`), before the forward clause. Command-level bindings never fire in a workspace (my first attempt; tests missed it using `:orbis` ctx).
✅ **Clickable**: thread cards (click = fold+focus, ThreadStack.pick), tertius band (click = focus), sidebar/tabs/roster already were.
✅ **Permanent tertius band** (`Panel.Tertius`, replaced the Ticker as the center's bottom band): input line + last-2 receipts. Focus via **click or `:`** (Space is fold now). De-duped — removed the StatusBar :orchestrate clause (52849bc). Bare text PASSES THROUGH → posts to the machine root thread (3bcbdff); verbs are shortcuts over the MCP toolset.
✅ **Hot-reload** (3af2be3): `mise run console:reload` (2nd terminal) = `mix compile && touch .reload`; cockpit reloads Console.* modules on the 500ms tick. INTENTIONAL + compile-gated (never auto-on-save). Render/keymap/panel edits live; STATE-SHAPE changes still need `console:run`.
✅ `Panel.TicketBoard` (fbb03f5, pure render, NOT yet wired into a layout).
✅ **3.4 layout restructure LANDED (code + green, pending Andrew's live eyes-on)**: `View.compose` now paints
**spine · funes rail · center** — a thin far-left SPINE (`wide_columns` = `spine_width(w)` ≈ w/8, clamped 14–22;
the Sidebar slimmed to Home + workspace headers, thread/crew sub-rows dropped since the center stack + CREW rail
carry them), the funes RAIL (`space.left` = `[Activity(NOW), Crew, Memory, Stack]`, stacked, digits 2–5), and the
center thread-stack + tertius. **Right rail KILLED**: `space.right = []` for both workspace and Orbis; the whole
carousel/pin machinery RETIRED (`visible_right`/`rail_context`/`pinned_head`/`Space.carousel`, `cycle_pane_view`,
`right_pane_view` state+reads, the `[`/`]` + Alt-`[`/`]` keymap, `border_tab_hit` click routing, `carousel_border`,
`pinned_boxes`/`intrinsic_height`). Focus SM unchanged: `left=[Sidebar]` (spine), `right=space.left` (rail) — H/L
spine↔rail. Leaves-subsystem (attach/preview/yank + `Panel.Leaves`) left LATENT (dormant — no rail pane focuses it;
full removal is Slice 5). console **854/0 green** (was 868 — dropped the retired carousel/leaf-preview tests; the 5
CrewTest "failures" in-sandbox are `~/.pi/profiles` write-blocks, green with sandbox off). GOTCHA: setting
`space.right = []` alone collapses the right column via the existing empty-carousel guards — the real work was the
new geometry + splitting the Sidebar into the spine.
✅ **Spine refined to an ICON DOCK (2026-08-31, Andrew's steer)**: the far-left spine is NOT text labels — it's a
home glyph `⌂` (the Orbis god-view) + one DIGIT per workspace (1-based, the super+1..9 mental model), no names
(the active space's name rides the status bar). `spine_width` ≈ w/16 clamp 7–11; `section_title(Sidebar)="WS"`;
`Panel.Sidebar` render is now `glyph_row/4` (the thread/crew sub-row rendering deleted — that paradigm lives in the
center stack). **Home is NOT cruft** — it's the god-view/dashboard (a funes survey across ALL workspaces); it stays
as the `⌂` entry. STILL TODO in the spine: global-tools entries (Tickets/Notes/settings) as glyphs — need switch
targets (Slice 3.5). Future (substrate, not 3.4): a workspace's content can be a pinned TUI (nvim/command) or a
nested tlon-workspace with its own projects.
✅ **Seed infra NEW (2026-08-31, Andrew asked)**: `modules/server/priv/seed/repo_knowledge.exs` (editable) +
`Server.Seed` (loads it, banks base self-knowledge FACTS keyed by `intent` + ensures baseline PROJECTS, idempotent) +
`mix server.seed` + wired into `Server.Bootstrap.ensure/0` so a fresh/reset scratch DB self-heals to "funes already
knows the basics". Seeded the cockpit DB (`modules/server/.dev/tlon.db`): workspace #1 ficciones, projects
general+excessibility+ex_riverside+ex_cortex (real repos under ~/projects), 10 constraint/stated facts (what Tlön
is, module layout, coordination model, substrate, runtime, DB, knowledge model, toolchain, gates). server 421/0 + 5
Seed tests.
NEXT: Andrew's live eyes via `console:run` (spine glyphs/width, rail density; workspaces now populated with projects+knowledge).
✅ **Interactive y/n confirm LANDED (2026-08-31)**: a consequential verb (`open`/`approve`) now ARMS
`pending_confirm: %{action, ctx, summary}` (cockpit) + flashes `⏸ <summary>? — y to confirm · n to cancel`;
`y` fires `Console.Orchestrator.confirm/2`, any other key cancels — a top-priority Keymap modal gate
(precedes even the input modal + a live terminal), mirroring the `pending_delete` two-key pattern. The arm
rides the effect (`{:confirm_orchestrate, arm}`) since the keymap clears the arm on `y` (same as
`{:remove_workspace, id}`). Keymap 5 new tests green; console 876/0 (5 CrewTest sandbox write-blocks green
with sandbox off). NOTE: cancel leaves the arm flash stale for one render — consistent with `pending_delete`'s
"press d again" behaviour; not worth a cancel-flash effect.
⏳ REMAINING: **3.5** wire the Tickets/Notes boards + STACK-zoom embedded lazygit + right-rail click actions (git commit→diff, triage→jump — these reuse commit_detail/focus_thread but need Focus-struct wiring; setting `status_detail` may be the simpler path) · v2 tertius **agent** (LLM interprets intent, folds into Slice 4). Small spine follow-ups Andrew flagged: a **settings/global-tools** entry in the spine (Tickets/Notes), and the "fat Slack sidebar" paradigm stays (it lives in the center thread-stack).

**Goal:** Reshape the cockpit to **spine · left rail · center thread-stack · bottom meta input** (2026-08-30 refinement). **Spine** (thin, Hyprland `super+1..9`): workspaces **+** global `Inbox/Tickets`/`Notes`; pinned apps allowed. **Left rail** of funes panels: top = active project + `⚙` + repo fuzzy-switch `Ctrl+O`; then `NOW`/ATTENTION, CREW, MEMORY, STACK. **Center = a vertical stack of foldable Slack-style thread cards** (the heart — see "The cockpit" above): folded = header (title·lead·stage) so the stack IS the thread list; unfolded (`z`) = conversation + artifacts + a **per-thread reply input**; the most-recently-active thread unfolded by default. **Bottom = the permanent `tertius ▸` meta input** (replaces the `:` stopgap). The old right rail (STACK/MEMORY) dies into the left rail. Two boards reachable as full-screen rail zooms: the **Tickets board** (per-workspace capture→triage→backlog→doing→done, no ceremony) and the **SDLC pipeline board** (worklines intent→…→merged); a ticket *promotes* off Tickets into the pipeline. **Absorbs Slice 0's parked work:** 0.2 → the thread stack replaces the leaves/strip window model (idle standing lanes gone; a card per active thread by its lead); 0.3 → leaf/leader labels retired. Runs on the **tmux=session substrate**: switching a workspace switches the tmux session; global tools span all sessions via funes.

**Surfaces:** `cockpit.ex` (three-column → spine+rail+main layout, focus machine, screen-mode state), `keymap.ex` (`super+1..9` workspace jump, `Ctrl+O` project switch, in-rail number-jump, `Tab`, `+`/`_`, verb bar), existing panels re-homed (`triage`→NOW, `overview`/`leaves`→THREADS, `roster`/`crew`→CREW, `memory`, `stack`), a pipeline-board render (THREADS zoomed), the ghostty PTY embed for STACK-zoom.

**STACK-zoom = embedded lazygit.** STACK small = git read-model (branch/commits/files, glanceable, no PTY). `+`-zoom = a **real embedded lazygit** (`lazygit -p <path>` in a ghostty PTY) at the focused thread's worktree (`work/<slug>/`, wired in Slice 4), falling back to the project's repo (a repo picker when the project has several). `_` collapses back. Reuses the `Ctrl+Space` TERM↔NAV leader verbatim (lazygit captures keys like any PTY) — no new input model. Tames worktree sprawl: navigate by thread, git follows focus. **Infra:** add `lazygit` to the flake (system-only today).

**Acceptance:** two columns + spine, no redundant right rail; `super+1..9` switches workspace and re-scopes everything; `Ctrl+O` fuzzy-switches project; NOW/THREADS/CREW/MEMORY stack in the rail; the strip is thread-driven (idle lanes gone); `+`/`_` zoom (THREADS→board, NOW→inbox, STACK→lazygit at the focused worktree); no leaf/leader in labels; main follows focus. Builds on the landed `Ctrl+Space` TERM↔NAV + `h/l/H/L` focus machine.

**Note:** largest slice — decompose when reached. Mine `2026-08-20-tlon-lazygit-panels-design.md` + `2026-08-23-aleph-cockpit-clarity-*.md`, subordinate to the model above.

### Slice 4 — Lead-as-manager + any-stage entry + orchestrator staffing

**STATUS (in progress, 2026-08-31, autonomous):** decomposed into 4A worktree primitive → 4B thread→repo resolution → 4C console lazygit zoom → 4D coordination model.
✅ **4A — `Server.Worktree` LANDED** (server 440/0): lazy per-thread `git worktree add .worktrees/<slug> work/<slug>` (creates branch off HEAD or reuses it), `ensure/2` (idempotent), `prune/2` (`--force`, keeps the branch), `path/2`+`branch/1` pure. **Decision (Andrew):** real worktrees at `.worktrees/<slug>` — NOT `work/<slug>/`, which is already the live artifact-docs dir (`Scribe`/`Artifacts.Git` commit intent/spec/plan/review there in the MAIN tree; a worktree there would collide). `.worktrees/` ignored repo-locally via `.git/info/exclude` (never a committed `.gitignore`). Slug charset re-validated (no traversal). 10 tests, real temp git repos.
✅ **4B — thread→project→repo resolution LANDED** (was inert): `Server.Projects.repo_for_thread/1` + facade `Server.repo_for_thread/1` (id or struct) → `{:ok, ~-expanded primary-repo path}` | `{:error, :no_repo|:no_thread}`. Explicit `project_id` uses THAT project's first repo (never borrows another's); nil project falls back to the workspace's first repo-bearing project. `repos` = JSON `[%{"name","path"}]`. 4 tests.
✅ **4C — console STACK-zoom embedded lazygit WIRED** (console 875/5 — 5 = known CrewTest sandbox blocks): tested primitives — `Server.worktree_for_thread/1` (facade: repo_for_thread + Worktree.ensure; a thread with a slug → `.worktrees/<slug>`, no slug → the repo itself) + `Console.Lazygit` (`command/1` builds `/bin/bash -lc "cd … && exec lazygit"`, shell-quoted; `available?/0`). Cockpit overlay: `lazygit` state field; **Enter on the focused STACK rail pane** (`apply_effect(:tlon_enter)` `Panel.Stack` branch) → `open_lazygit` → `Sessions.ensure({:lazygit, id}, …)` → full-frame `lazygit_placements` (`Panel.Terminal` over the PTY); `Ctrl+Space` collapses; keys/clicks/wheel route to the lazygit PTY while up; the tick `reconcile_lazygit` collapses a quit-from-inside pane. **LIVE-ONLY (Andrew's kitty pass):** PTY render + key routing + resize-on-window-change (spawn dims only for now). FOLLOW-UP: add `lazygit` to the flake (on PATH today at /usr/sbin, so it works; flake entry is for reproducibility). NEEDS `console:run` (new state field).
✅ **4D substrate BUILT (2026-08-31)** — design in `docs/plans/2026-08-31-lead-as-manager-coordination-design.md` (brainstormed w/ Andrew). server 451/0, console 879/5(sandbox):
  • **4D-1 any-stage entry**: `Workline.open(:stage)` (default intent; validated ∈ ring−merged) + `open_titled/3` (title→slug) + `Thread.workline_changeset` casts `:stage`. Opening later sets the start, doesn't backfill owed artifacts, doesn't gate.
  • **4D-2 parent link + report-up**: migration `thread.parent_thread_id` (self-FK, unlink-not-cascade) + `belongs_to :parent` + `open_changeset` casts it; `Channel.close_thread` reports up — a closed CHILD posts `✅ child #N “title” closed` into the parent `@`-mentioning its lead (the console mention router wakes them).
  • **4D-3 toolset**: `StaffLeaf`→ now parents the child at the caller + inherits project (→StaffChild in Slice 5); new first-class **`assign_lead`** MCP tool (thread_id+handle, registered in endpoint.ex).
  • **4D-4 verb wiring + ATTENTION**: `Orchestrator.confirm({:open,stage,title})` → `Server.open_workline` (stage) / plain thread (nil=explore); `confirm({:approve,n})` → `Server.approve_workline` (un-stubbed). NOW pane (`Panel.Activity`) now leads with a **⏸ AWAITING YOU** gate list from cached `workline_statuses` (new `gates` probe on the @probe_ms cadence).
⏳ **4D-5 tertius orchestrator mandate** (LEFT — config + LIVE-tuned): tertius archetype/mandate `surveyor`→orchestrator + its brief (triage intents on the root thread, open work, assign leads, surface gates, don't build). A prompt, iterated with the running agent — Andrew's live step. Also LIVE: does tertius/leads actually delegate well (the whole loop feeling right).

**Goal:** Make the coordination model real, not just displayed. A lead delegates (staffs crew / spins child threads / assigns a reviewer) rather than building. Threads open at any stage. tertius actually orchestrates intake + escalation (with human gates).

**Surfaces:** server — `staff_leaf`/`spawn_crew`/`open_thread` (tool.ex), the workline stage machine (`advance_stage`, gates), lead assignment (`Channel.assign_lead`), the orchestrator's Maintain loop; console — the lead conversation main panel, gate surfacing into ATTENTION.

**Acceptance:** opening a thread at `review`/`build`/untracked works and owes the right artifacts; a **review** thread targets either a local diff or an external PR (backend-pluggable — see "Local-first" above; local mode now, GitHub/GitLab PR adapter follow-on); a lead, asked to build, delegates to crew/child threads and reports up; tertius routes a new intent to a lead and surfaces the spec/merge gates + escalations into ATTENTION; the two human gates park in `awaiting:andrew`.

**Note:** mine `2026-08-27-ai-native-sdlc-workline-design.md`, `2026-08-22-per-thread-agents-design.md`, `2026-08-19-orbis-tertius-meta-thread-design.md` — subordinate.

### Slice 5 — Nomenclature retirement + doc supersession

**STATUS (2026-08-31, partial — done what's SAFE, deferred what would break the live cockpit):**
✅ **Server side clean**: `grep -rEin 'leaf|leader' modules/server/lib` returns nothing — `StaffLeaf`→`StaffChild` + `staff_leaf`→`staff_child` (module + wire name + all refs + tests + tertius mandate), and every server comment/agent-facing doc reworded to thread/child/lead.
✅ **Doc supersession**: `2026-08-22-per-thread-agents-design.md` + `2026-08-19-orbis-tertius-meta-thread-design.md` stamped SUPERSEDED, pointing at this plan + the 4D design.
⏳ **Console code rename DEFERRED (deliberate — needs a live-verified pass, not a blind mechanical sweep).** Two hazards make a mechanical `leaf`/`leader` sweep unsafe on the running cockpit:
  1. **`leader` is overloaded**: `leader_pending?`/`clear_leader`/"the leader: Ctrl+Space" is the **keymap prefix key** (correct term — MUST stay), NOT the coordination lead. Only `focused_session {:leader, name}` and the doc-comments mean the coordination sense. A blind rename corrupts the keymap.
  2. **The `leaf`-attach subsystem is dormant DEAD CODE slated for REMOVAL, not rename** (`Panel.Leaves`, `{:leaf,id}`/`{:leader,name}` `focused_session`, `attach_leaf`, `jump_to_leaf`, `Console.LeafWindow`, `@leaf_window ~r/^t\d+$/`) — tangled through the live tmux window routing. `@leaf_window ~r/^t\d+$/` and the `t<id>` window pattern are a **runtime tmux contract**. This should be a focused removal pass with Andrew's live cockpit, since it touches window routing he runs.
  **DOCUMENTED SURVIVORS** (intentional, keep): keymap `leader`/`leader_pending?` (prefix key — right word); the dormant leaves-subsystem identifiers (pending removal, above). **Remaining console rename** = the coordination `{:leader,name}`→`{:lead,name}` + comment vocab in `cockpit.ex`/`view.ex`/`keymap.ex`/`machine_chat/*`/`panel/*`, best done alongside the leaves-subsystem removal.

**Acceptance (revised):** server lib grep-clean ✅; console coordination-`leader` + dead leaves-subsystem retired in a live-verified pass (deferred); both suites green ✅ (server 451/0, console 879/5-sandbox); lineage docs superseded ✅.

---

## Execution notes

- **Execution:** autonomous (2026-08-30 — Andrew: "let you cook … won't try it until we're done … do whatever"). Order at builder's discretion in dependency order; verify by tests + gates (Andrew is not eye-passing between slices), commit small, report progress.
- **Order:** 0 → 1 → 2 → 3 → 4 → 5. **Slice 0** — 0.1 done, rest parked into 3. **Slice 1** — orchestrator command line (highest new value, lives in the current cockpit). **Slice 2** — the Workspace▸Project▸Thread data model + CRUD (prereq for the spine/switcher). **Slice 3** — the big UX reshape (two-column lazygit cockpit; absorbs 0.2/0.3). **Slice 4** — makes the coordination model real (lead-as-manager, any-stage, orchestrator staffing, per-thread worktrees). **Slice 5** — cleans the language and archives lineage.
- **Discipline:** TDD every task (RED → GREEN → REFACTOR), commit small, run both module suites + the machine gate (`flake:check` / `home:switch`) before calling a slice green — module unit suites alone are NOT the gate for this repo.
- **Dogfood:** each slice should be usable live in the running cockpit before the next starts.
