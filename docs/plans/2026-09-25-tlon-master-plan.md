# Tlön — the master plan (2026-09-25)

Supersedes `2026-09-17-ficciones-master-plan.md` (its surface table and sequence) and folds in
the morning's `tlon-tui-focus` notes. One document: the north star, what is measured to be true,
the UX law, what is dropped, and the sequence with a check per piece. Pieces more than one step
out are named, not detailed (the roadmap lesson, 2026-09-01). When a piece is built its row is
updated here; nothing is "done" until its check is green.

Andrew, 2026-09-25: "neovim was a too many dabs thought. tlon/the tui is and should be the
primary … getting all the underlying data in shape and then focusing on the tui is the move.
ficciones/the rest of my computer is in pretty good shape so it's time to move back into the AI
business." And: "i haven't used tlon much because it's like so close to something very cool" —
"i always refactor better than i write."

---

## 0 · North star

> **Tlön is one always-up brain with one primary surface: the console TUI.** The desktop
> (ficciones) is done enough; it integrates with Tlön through a sidebar, not the other way round.
> The thread is the record; the terminal is where the work happens; the operator sees only what
> needs the operator.

Three surfaces, one ranking:

1. **The console TUI** — primary. Everything is reachable here; every piece below lands here first.
2. **The shell sidebar** — the desktop door: needs-you, a reply box, a terminal that follows the
   selected thread. Built after the TUI hierarchy holds, so it copies something that works.
3. **The web UI** — frozen. It exists (`:4042`, sidebar · thread · composer · triage · roster ·
   tickets · health) and stays running, but takes no new features until the TUI pass is done;
   then it mirrors the TUI's hierarchy, not its own.

Dropped: **Neovim / asterion** (7 commits, unused since 2026-09-17). The `/api` door it proved
stays — the sidebar and the web ride it.

## 1 · What is true (measured 2026-09-25, not assumed)

**The engine is sound enough.** Andrew's read, and the day's evidence agrees: threads as the
record, facts with certainty + forgetting, worklines, per-thread worktrees, the switchboard
(addressed delivery, coalescing, warmth-gating), staffing on Oban's cron, Postgres, the memory
pass. `mise run server:check`: 667 tests + 9 steering evals green.

**The core loop works, live.** Post to a thread that has a project → the staffing pass spawns the
lead in a worktree of that project's repo within a minute → it reads, works, replies in the thread.
Thread #15 (excessibility): asked at 09:19, summary at 09:20, README split committed on
`work/orient-what-is-excessibility` by 09:33, fact #25 banked on the way.

**Nobody had used it.** The live store held 9 threads / 15 messages after 1,331 commits. Every
fault the day found was a fault use would have found in an hour:

| Found | Cause | Fixed |
|---|---|---|
| every pi coworker started with no brief (`tlon error: undefined is not an object`) | adapter read `north_star`/`chatter`; server sends `goal`/`recent` | `6b5c7c4` + a fixture captured from the live server |
| TUI-opened threads ran their coworker in `$HOME` | the default project's repo was the scope glob `modules/*`, `Path.expand`ed | `e6f633e`; project rows now name real checkouts |
| staffing failed every minute for 31 h (2,211 discarded jobs), silently | `tmux: enoent` — the unit's boot-time PATH predates the nix profile | `2bc2cd0` (lands on the next `home:switch`) |
| four "still on it (45s) — bash: …" posts between an ask and its answer | the heartbeat | `15f3b48`, removed on both harnesses |
| a coworker sat 4+ minutes on a **permission prompt** (`eval "$(mise activate bash)"`, thread #80) and the thread said "still on it" | attention state is not derived; nothing rolls a prompt into the thread | piece A, `cf77ab8` |
| a plain README task became a workline mid-turn, got a `▶ BUILD` brief, its branch renamed, then "branch does not exist" | auto-track promotes on any commit; the artifact gate checks `TLON_WORKLINE_ROOT` (ficciones) whatever repo the thread is in | piece B, `11db11d` `b9b5dfb` `3b0f08f` |

**The corpus exists now.** 62 Claude Code conversations imported as closed threads on their
projects (`server:import-claude`, `72a09f5`); the memory pass is mining them (93 facts and
rising — "verify style changes on screenshots, not source", the Astal migration decision, the
Lua `getoption` gotcha). Projects: ficciones, excessibility, menard, ex_riverside, ex_cortex.
Three live starter threads: #15 (excessibility README, done, awaiting review), #80 (menard hex
checklist, blocked on the permission prompt above), #81 (menard drift plan, written).

**Field position** (survey 2026-09-17 §3) unchanged: thread-as-record, certainty-ranked facts,
artifact-gated worklines, dossier-not-transcript, bucket routing, evals-on-steering are the
differentiators. Keep them; don't flatten them to match the field.

## 2 · The law — five rules the TUI is built to

These extend `2026-09-08-cockpit-ux-principles-design.md` §1 (copy the habit, one noun one
place, the conversation is the record, orientation always on, keys follow focus, scope is the
workspace). Those still hold. These are the ones the day added.

**R1 · /focus — the thread shows the operator only what needs the operator.** Claude Code's
`/focus` shows the final message and hides the tool calls; Tlön makes the same cut between the
thread and the terminal:

| Thread (focus) | Terminal (underneath) |
|---|---|
| the operator's asks | tool calls, diffs as they're written |
| the coworker's answer — one per turn | "running mix test…", retries, dead ends |
| decisions, blockers, questions **for you**, permission prompts | the coworker's own narration |
| COMMITS as rows, CHECKS as rows | the commit's diff (open from the row) |

Presence (thinking / idle / **waiting**, and for how long) is the only live signal a thread shows
about the work. A coworker never posts progress; the server derives it.

**R2 · Waiting is a first-class state, and it reaches you.** A session is `working`, `idle` or
`waiting` (a permission prompt, a question, an interrupt), derived by the server from the pane
per harness (design §4 already specifies this — it is not built). `waiting` rolls a `prompt`
message into the thread, flips the rail badge to `!`, and toasts the shell. You answer it **from
the thread's reply box**; the terminal is never the only place a thing can be answered.

**R3 · Enter queues, Ctrl+Enter sends now.** (Claude Code's queue.) Enter posts to the thread at
once and the coworker reads it at its next turn boundary — no interruption, no lost context.
Ctrl+Enter interrupts the current turn and delivers now. The composer shows the queue ("2 queued
for hronir"); a queued message is marked in the thread until it lands.

**R4 · Workspace ▸ Project ▸ Thread, and the project is where the code is.** A thread has a
project; the project has one repo; the coworker works in that repo's worktree. Nothing opens a
thread without a project (the TUI picks the last-used one). Closed threads are history, browsable
and searchable, one keystroke from the rail — you start work by finding the last time you
touched something, not from a blank box.

**R5 · Worklines are opt-in.** A thread is a conversation. It becomes a workline (stages, owed
artifacts, gates) when the operator says so — the `workline` verb, or "promote" on a thread —
never because a coworker happened to commit. The gate checks the thread's own repo.

**Kept from the shell:** the palette law (every surface wears the generated palette, no client
names a hue) and the one-brain rule (every surface reads the same `Server.*` contexts and Bus
topics; no client owns state).

## 3 · The sequence

Detailed for A–D (the next steps); named for E–H. Each piece is a **Tlön thread on project
ficciones** — Tlön builds Tlön, and the threads are the dogfood that finds the next fault. Each
piece ends with a live pass in the cockpit with Andrew (`mise run console:run:tmux` + the
drive-cockpit skill), and the faults that pass finds go into the piece's thread before the next
piece starts.

| # | Piece | Detail | Check |
|---|---|---|---|
| **A** ✅ BUILT 2026-09-25 (`cf77ab8`…`8e78ea7`, merged; live on the service: thread #82 — posted 10:23:21, the coworker hit pi's `eval` dialog, the `⚑ waiting on you` row landed 10:24:06, `server:post 82 y` answered it from the thread at 10:24:19, the coworker replied at 10:24:21). The prompt IS the state (a `prompt` message, no session column). The poller runs on the service (`TLON_START_ATTENTION=1` lands on the next `home:switch`; started by hand until then). Also: a discarded Oban job posts once to #general. | **Attention: waiting reaches you** (R2). `Server.Session` gets `attention: working \| idle \| waiting` — derived per harness by matching the pane text (pi-permission-system's `▶ (y) Yes` block; Claude Code's permission dialog and `?` question line; the plain input prompt = idle), polled while warm (`Server.Jobs.Staff` already lists windows each minute; a 5 s poll while a session is warm is its own job). A `waiting` transition rolls a `prompt` message (`kind: prompt`, `payload: {options}`) into the thread as `tlon`; the rail badge reads it; the shell's needs-you toast reads it. The reply box on a `prompt` message answers it: the reply is sent to the pane as keys (`y` / `n` / the text), not posted as chat. Also here: a discarded Oban job posts to `#general` once (the 31-hour silence). | Server: `Server.Attention` + `session.attention` column + `message.kind/payload`; adapters: none (derived, not reported). Console: badge + inline answer. Shell: toast reads `waiting`. | `mise run server:test` scenarios per harness on captured pane text; live: start a coworker on a task that needs `eval`, see `!` on the rail and the toast within 10 s, answer `y` from the reply box, watch the pane continue |
| **B** ◐ IN FLIGHT 2026-09-25 03:43 — a second Claude Code session in the main tree (test-first: `Artifacts.Git` resolves the root per thread; auto-track removed from both adapters) | **Worklines opt-in; the gate checks the thread's repo** (R5). `track_thread` stops being called mechanically (cc-track.ts, extension turn_end); `Server.Workline.promote/1` is reached only from the operator's `workline` verb / TUI promote. `Artifacts.Git` and `Scribe` resolve the root from `Server.repo_for_thread/1`, falling back to `TLON_WORKLINE_ROOT` only for threads with no project. The `▶ STAGE` briefs post only on worklines. | `Server.Workline`, `Server.Workline.Artifacts.Git`, `Scribe`, adapters' cc-track | the #15 scenario as a test: a commit on a plain thread leaves `stage` nil; a workline on excessibility passes `:branch` against excessibility; `server:check` green |
| **C** | **Queue vs now** (R3). `message.delivery: "queued" \| "now"` (default queued). The switchboard delivers `queued` to a session whose attention is `idle` (or at its next `presence_idle`) and `now` immediately — for a `working` session, "now" means the arbiter sends the harness's interrupt (Escape for pi and Claude Code) before the text. The TUI composer: Enter → queued, Ctrl+Enter → now (the kitty keyboard protocol distinguishes them on the bare terminal; under tmux Ctrl+Enter is CSI-u — test both); the footer shows the queue count for the open thread; queued rows render dimmed until `delivered_at`. `server:post` gains `--now`. | `Server.Switchboard`, `Server.Message`, `Server.Arbiter.Tmux.wake/2`, console composer + keymap | test: two posts while a session is `working` → both stay undelivered until idle, coalesced into one wake; a `now` post → interrupt + delivery at once. Live: type while hronir works, watch it land after its reply |
| **D** | **Hierarchy in the TUI** (R4). New thread → a project picker (last-used default; `Alt+n` still one gesture: type, Enter, the picker only when you tab to it). The rail shows the project under the workspace when a workspace has more than one. **History**: a `closed` filter on the rail (`h`), the 62 imported conversations in it, `/` searches (`Server.Search.history`) across open + closed; Enter on a closed thread opens it read-only with `r` = reopen (staffs it) and `n` = new thread citing it (`#id`). | `Server.Board.sidebar` (today: open only), console rail + new_thread + a history view; `Server.Search` exists | `Board.sidebar(closed: true)` test; live: open the cockpit, find "Caelestia to Astral migration" by search, spin a new thread off it, its brief cites #53 |
| **E** ◐ IN FLIGHT 2026-09-25 — #81's plan written; the menard-side Claude Code session is reading it | **menard from its own repo.** Thread #81 has hronir's plan (submodule at `modules/menard` pinned to menard's `main`; `bin/menard` `MENARD_CWD`; the server's `{:menard, path:}` dep follows). Andrew edits the plan; the piece is the plan's commits. | `#81` | `mise run menard -- outline` runs the standalone code (has `source.ex`); `server:check` green; a fresh clone + `git submodule update` works |
| **F** | **The TUI eye pass.** The list only exists after A–D are live: the things that feel wrong, in the order Andrew hits them. Known candidates: the drawer's ten tabs (which four matter?), the top bar's worktree path, the terminal pane's default mode, the switcher (`^⇧K` exists over threads · channels · globals; closed threads and `@`/`#` come with D), key hints. Each item is its own small commit. | live pass, one thread | Andrew: "I'd use this tomorrow" |
| **G** | **The shell sidebar.** The AI popup becomes a full sidebar (Hyprland special workspace or a docked astal window), distinct from notifications: needs-you threads (from `/api/sidebar` + attention), a reply box that posts through `/api`, and a `libghostty`/foot terminal attached to the selected thread's coworker window (`GET /api/threads/:id/terminal`), following the selected project's folder. Reads the same rows as the TUI; owns nothing. Design doc when it starts. | `modules/desktop/shell/panes/Agents.tsx` (92 lines, polls `tlon-cli shell-status`) grows into it; `/api` gains what it needs | `shot:*` gate on both palettes; live: answer a permission prompt from the sidebar |
| **H** | **Experiments** (evals, not builds) — now possible: the corpus is 62 threads + ~100 mined facts. Query-driven brief vs fixed budget; forget-at-recall vs mem0's four verdicts; CHECKS up the evidence hierarchy. `docs/research/2026-09-18-one-brain-h-experiments.md` has the shapes. | research doc | a written result in `docs/research/` |
| **I** | **Web UI unfrozen** — mirrors D's hierarchy and A's attention; nothing the TUI doesn't have. | later | — |

**Why this order.** A first because it is the fault that makes Tlön feel dead: the coworker is
waiting on you and you can't tell. B before C because C's "idle" needs threads that don't mutate
under the coworker. C before D because D's history/reopen posts into threads and needs the queue
semantics. E is independent and can run as a coworker thread alongside A–D. F needs A–D live. G
copies F. H whenever there is an idle evening. I last.

**The working method for every piece:** open a thread on ficciones with the piece's ask as the
first message; hronir (or Claude Code via `server:claude`) takes the first cut on a work branch;
Andrew reviews in the thread and the branch (refactor, not write); the piece's live pass is the
gate. The starters (#15, #80, #81) are the first three of these.

## 4 · Not doing

- **No new surfaces.** No Neovim work; no web features; no second door to any verb.
- **No new plan docs per piece** unless the piece is G (the sidebar needs a design). A piece's
  thread is its plan; this document is its index.
- **No heartbeats, no progress prose in threads** — R1.
- **No "match the field" flattening** of facts/worklines/briefs; the differentiators stay.

## 5 · Open questions (Andrew's, not the machine's)

1. **Attention per harness (A):** derive from the pane text (herdr/claude-tmux style, works for
   any harness, brittle to a redraw) or have the harness declare it (pi's permission-system
   extension and Claude Code's `PermissionRequest` hook can call `presence_waiting`; exact, but
   every harness must cooperate)? Proposal: **both** — declared when available, derived as the
   fallback, and the pane match is the test oracle.
2. **menard (E):** submodule (hronir's plan) or flake input + a `menard:sync` task? Submodule is
   simpler for the server's path dep; a flake input is cleaner for Nix but the server compiles
   from `../menard` at dev time regardless. Lean submodule.
3. **The centre seat (tertius, the surveyor on pi/glm):** it runs whenever the workspace does and
   drains the ollama bucket for a conversational seat nobody talks to. Keep it up always, or
   spawn it on first use? Decide in F.

## 6 · Index

- `2026-09-17-ficciones-master-plan.md` — superseded surfaces; §5 (Neovim findings) is history.
- `2026-09-08-cockpit-ux-principles-design.md` — still the TUI's principles and frame; §4's
  schema gaps are pieces A and C here.
- `2026-09-08-tlon-one-brain-umbrella.md` — built; the web UI's freeze is §0 here.
- `2026-08-27-ai-native-sdlc-workline-design.md` — worklines; piece B makes them opt-in.
- `2026-09-02-astal-shell-design.md` — the shell; piece G adds the sidebar.
- `2026-09-17-orchestrator-field-survey.md` §4 — the adopt list; #2 (needs-you) is piece A.
- `docs/research/2026-09-18-one-brain-h-experiments.md` — piece H's shapes.

Memory: `tlon-direction-tui-primary` (2026-09-25).
