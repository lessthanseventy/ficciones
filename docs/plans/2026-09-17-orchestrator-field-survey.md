# The orchestrator field, by mechanism — what Tlön adopts, keeps, and skips

2026-09-17. Companion to `2026-09-17-omarchy-atlas-steals.md` (the north star: Tlön steals every
good idea from the field and differentiates on purpose). Three surveys, one per class, run by
Sonnet investigators with web access; §4 is the synthesis and the decision list. Every claim in
§1–§3 carries the URL it came from; "–" means *not found in sources*, not *absent*.

Status: §1 banked · §2 (hosted/cloud) pending · §3 (frameworks/protocols) pending · §4 pending.

---

## 1 · Local / TUI / desktop orchestrators (16 projects)

| Project | Thesis | Distinctive mechanisms | What it has that Tlön does not |
|---|---|---|---|
| **Claude Squad** ([smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad)) | TUI multiplexer for several terminal agents at once. | tmux session per agent + worktree per branch; pause/resume keys; `--autoyes`; checkout-before-push review gate. | tmux-native pause/resume of a live PTY (Tlön restarts via dossier, doesn't freeze/thaw). |
| **CCManager** ([kbwo/ccmanager](https://github.com/kbwo/ccmanager)) | Session manager across 9 CLI agent brands. | Per-tool state-detection heuristics → idle/busy/waiting live; **hooks on state change** (shell out to `noti` etc.); `.worktreeinclude` carries gitignored secrets/deps into new worktrees; optional devcontainer execution. | Multi-harness state polling beyond Claude, and a hook-on-state-change extension point. |
| **Crystal → Nimbalyst** ([stravu/crystal](https://github.com/stravu/crystal), [nimbalyst.com](https://nimbalyst.com/)) | Electron multi-session Claude Code/Codex in worktrees → "session kanban" workspace. | SQLite-persisted sessions; session **kanban board**; inline diff review; WYSIWYG editors (markdown/mockup/diagram/data-model) beside the session. | Sessions-as-cards kanban; non-code artifact editors beside the coding session. |
| **mux** ([coder/mux](https://github.com/coder/mux), [xum.coder.com](https://xum.coder.com/)) | Desktop+browser multiplexer; model-agnostic routing; "opportunistic compaction". | **Opportunistic compaction** — compress context proactively, not only at the limit, with a context-management dialog; git **divergence view** across worktrees/SSH remotes; per-session costs tab; local/worktree/remote-SSH execution chosen per task. | Proactive compaction as a named user-facing mechanism; a divergence view distinct from a diff. |
| **Conductor** ([conductor.build](https://www.conductor.build/)) | Mac app orchestrating Claude Code/Codex/Cursor/OpenCode in worktrees (Melty Labs, YC). | Workspace = worktree + branch + terminal + diff + review, archived on completion; only git-tracked files into new worktrees; "agent modes" + a **public API** for programmatic control. | An API for driving workspace creation/review from outside the app. |
| **Vibe Kanban** ([BloopAI/vibe-kanban](https://github.com/BloopAI/vibe-kanban); fork [easy-vibe-kanban](https://github.com/nagisasaka/easy-vibe-kanban)) | Kanban as the control surface for 10+ agents. | Issue → workspace 1:1; **inline PR-style comments on the diff sent back to the agent**; AI-generated PR descriptions; embedded browser with devtools/device emulation. | Card-as-unit-of-work; embedded browser preview. |
| **Superset** ([superset-sh/superset](https://github.com/superset-sh/superset), YC S26) | "Agentic IDE" for 100+ agents. | **N-way race**: same task under several agents/models in parallel worktrees, merge the winner; layered attention (indicators + chimes + dock badges); per-workspace browser preview + terminal presets; BYO-provider billing, no meter. | Best-of-N racing of the *same* task as a first-class workflow. |
| **Emdash** ([generalaction/emdash](https://github.com/generalaction/emdash), YC W26) | Open-source ADE wiring ticket trackers to agents. | Local SQLite; **8 tracker integrations** (Linear/GitHub/Jira/GitLab/Asana/Featurebase/Monday/Forgejo/Plain) dispatch a ticket into agent+worktree; remote SSH/SFTP execution with keychain creds; unified diff+PR+CI+merge dashboard. | External issue-tracker ingestion; native remote-host execution. |
| **Multica** ([multica-ai/multica](https://github.com/multica-ai/multica)) | Agents as assignable teammates on a shared tracker. | Full **tool-call/command/error replay log per issue**; inbox that pings only on blockers; **token cost per agent × issue**; retry-or-explain on failure; "squads" mixing humans+agents with a routing leader; **compound skills** = a solved problem turned into a playbook other agents inherit. | A first-class playbook-from-solved-task mechanism; cost broken out per agent per issue. |
| **Paperclip** ([paperclipai/paperclip](https://github.com/paperclipai/paperclip)) | "Zero-human company" control plane: org chart of agents with budgets and governance. | **Atomic task-checkout + budget-check** as one transaction; heartbeat resumption into the *same* task context; config **revisioned with rollback**; budgets scoped company/agent/project/goal/issue/provider/model with hard-stop pausing; explicit hierarchy (boss, title, job description). | Budget as an atomic gate, not a dashboard number; revisioned agent config. |
| **Gas Town** (Steve Yegge — [Medium](https://steve-yegge.medium.com/welcome-to-gas-town-4f25ee16dd04), [maggieappleton.com/gastown](https://maggieappleton.com/gastown), [DoltHub](https://www.dolthub.com/blog/2026-01-15-a-day-in-gas-town/), [TheNewStack](https://thenewstack.io/steve-yegges-ai-agent-orchestration-project-gas-town-comes-to-the-cloud-and-brings-the-wasteland-with-it/)) | Dozens of agents on the **Beads** issue tracker; sessions disposable, roles durable. | Beads = git+SQLite JSONL issue store, so a task and an agent's *identity* survive session death; **"seancing"** — a fresh session queries its dead predecessor's beads; strict roles (Mayor never codes · Polecats disposable single-task · Witness unsticks · Refinery owns the merge queue and will *reimplement* to resolve a conflict); cost "thousands a month". | Disposable-session/durable-identity as a stance; a merge-queue agent that reinvents on conflict; hard scope per role. |
| **Claude Code Agent Farm** ([Dicklesworthstone/claude_code_agent_farm](https://github.com/Dicklesworthstone/claude_code_agent_farm)) | 20–50 Claude Code agents in tmux for codebase-wide sweeps. | **Lock-file coordination**: agents claim files/features in `/coordination/` before touching them, stale locks (>2h) expire; heartbeat files + state JSON drive a dashboard; **adaptive idle timeout** = 3× the agent's own median cycle (30–600s); context-% per pane with broadcast `/clear`; progress `.md` files persist completion % across sessions. | File-level pessimistic locking within a shared sweep; per-agent adaptive idle timeout. |
| **Symphony** ([openai/symphony](https://github.com/openai/symphony); forks [kulichevskiy/symphony](https://github.com/kulichevskiy/symphony), [oh-my-symphony](https://github.com/cskwork/oh-my-symphony), [contrabass](https://github.com/junhoyeo/contrabass)) | A SPEC (not just an app) for tracked work → isolated autonomous runs with **proof of work** before landing. | Proof-of-work bundle per run: CI + PR review feedback + complexity analysis + a walkthrough **video**, all required to merge; ships as SPEC.md so it has 3+ reimplementations; reference impl watches a Linear board. | Proof-of-work as a named, enforced gate; a generated walkthrough video. |
| **Paseo** ([getpaseo/paseo](https://github.com/getpaseo/paseo)) | Self-hosted, no-telemetry multi-agent runner with mobile/voice. | On-device voice transcription by default; encrypted remote access from a phone; per-agent optional worktrees; 5 CLIs as interchangeable providers. | Voice dispatch and phone-native control as first-class. |
| **Mission Control** ([builderz-labs/mission-control](https://github.com/builderz-labs/mission-control)) | Minimal self-hosted control plane (SQLite, zero deps). | Runtime-agnostic dispatch; per-run spend; pause/inspect/review, kept thin (alpha). | Nothing beyond the fuller tools — proof the pattern is now a commodity shape. |
| **parallel-code** ([johannesjo/parallel-code](https://github.com/johannesjo/parallel-code)) | Single-dev runner for Claude Code/Codex/Gemini/Antigravity/Copilot. | **"AI Arena"** race mode; auto-**symlinks** `node_modules`/gitignored deps into worktrees instead of copying; **change-tour**: background-generated narrative walking you through the diff before merge; phone access via QR; desktop notif on CI completion. | A narrated "tour" of a diff as the default review artifact; symlink-not-copy deps. |

### Mechanism matrix

| Mechanism | Claude Squad | CCManager | Crystal | mux | Conductor | Vibe Kanban | Superset | Emdash | Multica | Paperclip | Gas Town | Agent Farm | Symphony | Paseo | Mission Control | parallel-code |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Record/history | tmux buffer | hook log | SQLite | costs+context log | workspace archive | task+exec log | session log | SQLite | **full tool-call replay** | heartbeat state + revisioned config | **Beads** (git+SQLite JSONL) | heartbeat + progress .md | CI/PR/video proof bundle | – | SQLite | change-tour |
| Git join | worktree/branch | worktree + `.worktreeinclude` | worktree | worktree/local/SSH | worktree/branch | worktree/branch | worktree/branch | worktree + SSH | branch→PR gate | worktree/branch | Beads branches, autonomous merge | branch, incremental commits | via harness | worktree optional | runtime-dependent | worktree, symlinked deps |
| Context assembly | – | – | – | **opportunistic compaction** | – | – | – | – | – | heartbeat resume (same context) | **seancing** | context-% + broadcast `/clear` | – | – | – | – |
| Cost | – | – | – | **costs tab** | – | – | BYO, no meter | – | **per agent×issue** | **atomic budget gate** | named, no gate | – | – | – | per-run spend | – |
| Attention/idle | – | **idle/busy/waiting** | – | sidebar status | – | – | chimes+badges | – | blocker-only inbox | – | perpetual queue | **adaptive idle timeout** | – | – | – | CI-complete notif |
| Sandboxing | tmux+worktree | **devcontainer** | – | worktree/SSH | worktree | worktree | worktree, per-workspace ports | worktree/SSH | your runtime | worktree | none named | tmux panes | harness-dependent | self-hosted | – | worktree |
| Review | checkout-before-push | – | inline diff | integrated | diff+checks | **inline comments→agent** | diff viewer | diff+PR+CI | diff+PR, log linked | approval gates | Refinery merge queue | diff summaries | **proof-of-work required** | – | review failures | diff + **AI tour** |
| Rotation/resume | pause/resume | copy session into new worktree | card resume | session resume | archive/reopen | – | – | – | – | **heartbeat resume** | **seancing** | continuation prompts | – | – | – | – |
| Multi-harness | 4 | **9** | 2 | many (routed) | 4 | **10+** | many | 4+ | Claude only | any | Claude-centric | Claude only | agnostic spec | 5 | any | 5 |
| UI | TUI | TUI | Electron | desktop+browser | Mac | web kanban | desktop IDE | desktop | web | web | CLI/tmux + cloud | tmux dashboard | varies | desktop+mobile | web | desktop |

### Field baseline (table stakes)

1. **Worktree per agent/task** — universal across all 16.
2. **Branch-per-task lifecycle ending in diff review → PR/merge → archive.**
3. **Multi-harness / BYO agent** (≥2 CLIs; single-harness is the exception).
4. **Visible per-session status** (idle/busy/waiting) wherever >1 agent runs.
5. **Diff viewer as the primary review surface**, increasingly with inline comments that round-trip to the agent.
6. **Local-first SQLite state**, telemetry opt-in.
7. **A "ping me when it needs me" signal** (badges, chimes, hooks, CI notifs).
8. **BYO subscription/API-key billing** — every commercial entrant. Tlön's "which bucket am I draining" framing is the market norm, not a novelty.

### Genuinely novel — steal candidates

- **Opportunistic compaction** (mux) — compress before you're forced to.
- **Seancing / disposable session, durable identity** (Gas Town/Beads) — the fresh session *queries* its predecessor's record rather than receiving one injected brief. Closest to Tlön's dossier; goes further by making identity + unfinished-work state queryable.
- **Atomic checkout + budget gate** (Paperclip) — claim and spend-check in one transaction.
- **A merge-queue agent empowered to reimplement on conflict** (Gas Town Refinery) — everyone else stops at a conflict.
- **Proof-of-work as an enforced landing gate**, video included (Symphony).
- **File-level pessimistic locking in a shared sweep** + **adaptive per-agent idle timeout** (Agent Farm).
- **N-way race of the same task** (Superset, parallel-code).
- **Compound skills** — a solved issue becomes a playbook others inherit (Multica).
- **AI-generated change tour** as the default review artifact (parallel-code).
- **Hooks on session state change** (CCManager) and **inline diff comments → agent** (Vibe Kanban).

---

## 2 · Hosted / cloud / IDE platforms

_pending — survey running._

## 3 · Frameworks, protocols, memory

_pending — survey running._

## 4 · Synthesis — adopt · keep · skip

_pending — written once §2–§3 land._
