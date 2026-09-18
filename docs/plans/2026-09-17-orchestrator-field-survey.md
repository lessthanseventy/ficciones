# The orchestrator field, by mechanism — what Tlön adopts, keeps, and skips

2026-09-17. Companion to `2026-09-17-omarchy-atlas-steals.md` (the north star: Tlön steals every
good idea from the field and differentiates on purpose). Three surveys, one per class, run by
Sonnet investigators with web access; §4 is the synthesis and the decision list. Every claim in
§1–§3 carries the URL it came from; "–" means *not found in sources*, not *absent*.

Status: §1–§2 banked · §3 (frameworks/protocols) pending · §4 pending.

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

## 2 · Hosted / cloud / IDE platforms (15 + 3 noted)

| Platform | Thesis | Distinctive mechanisms | What it has that Tlön does not |
|---|---|---|---|
| **OpenAI Codex Cloud + app** ([intro](https://openai.com/index/introducing-codex/), [upgrades](https://openai.com/index/introducing-upgrades-to-codex/), [pricing](https://developers.openai.com/codex/pricing)) | ChatGPT-native async coding: hand a task from chat/IDE/CLI/GitHub, get a PR. | Container per task → PR; the Codex app (in ChatGPT desktop since 2026-07) as a manager surface for many long-running agents; cost = token **credits** in a 5h rolling window pooled with chat usage, task and review counts rate-limited together. | Plan-wide usage pooling across chat + cloud + review; GitHub review-comment-triggered re-runs. |
| **Cursor cloud agents** ([docs](https://cursor.com/docs/cloud-agent)) | Move a bounded task onto a dedicated VM; come back to a PR with evidence. | VM per agent (repo+deps+secrets+network); agent **attaches proof to the PR** (screenshots, videos, test logs); aimed at narrow repeatable task shapes. | Evidence auto-attached to the review artifact. |
| **Claude Code on the web** ([docs](https://code.claude.com/docs/en/claude-code-on-the-web)) | The same session on managed infra, reachable from browser/mobile/terminal/routines. | Named reusable **cloud environments**; **`--cloud` / `--teleport`** one-way handoff with git-state preflight (clean tree, same repo, branch pushed) restoring full history; **auto-fix**: subscribes to PR webhooks (CI failures, review comments) and pushes fixes, asking only on ambiguous/architectural comments; diffs from raw blobs. **Projects**: "one conversation where Claude coordinates parallel cloud sessions and reports back". | Webhook-driven CI/review response loop; local↔cloud teleport with preflight; a supervisor-of-sessions layer. |
| **Claude Code subagents / agent teams / hooks** ([agent-teams](https://code.claude.com/docs/en/agent-teams), [sub-agents](https://code.claude.com/docs/en/sub-agents)) | Two tiers of parallelism inside one CLI: subagents (fire-and-report) vs. teams (peers, direct messaging, shared task list). | **Mailbox** = JSON file per agent, delivery confirmed on write; **shared task list with dependency edges**, file-locked claims, completion auto-unblocks; **hooks as gates**: `TeammateIdle`/`TaskCreated`/`TaskCompleted`, exit 2 = block + feedback; documented **adversarial-debate** pattern against anchoring. Team state is deleted at session end. | Dependency-gated tasks with locked claims as a product feature; hook-enforced idle/creation/completion gates. No durable server-side record — Tlön's differentiator. |
| **Devin** ([knowledge](https://docs.devin.ai/product-guides/knowledge), [review](https://cognition.com/blog/devin-review)) | The "autonomous employee": ticket in, PR out, reviews others' PRs. | **Knowledge vs. Playbooks**: Knowledge = persistent facts recalled by trigger-match, repo/org scoped; Playbooks = imperative procedures with success criteria + guardrails; use both. **Devin Review** (`/devin review`): findings bucketed Critical/Warning by confidence, resolvable inline, also a GitHub Action. | Trigger-recalled knowledge (vs. one fixed brief); severity/confidence taxonomy on findings; reviewer decoupled from author. |
| **Google Jules** ([jules.google](https://jules.google/)) | Assign-and-walk-away, GitHub-bound, plan-first. | Mandatory **plan-then-execute** gate you can edit before code; public **API** for CI/Actions/Slack/Linear/Jira; VM per task; browser notification on completion. | Embeddable API; browser push as the attention channel. |
| **Warp / Oz** ([oz](https://www.warp.dev/oz), [blog](https://www.warp.dev/blog/oz-orchestration-platform-cloud-agents)) | Terminal-as-ADE plus an unbounded-agents orchestration layer. | **`oz schedule --skill … --cron …`** — cron runs as a CLI primitive; fan-out-per-unit-of-work (one agent per diagram type); **session-sharing links** to watch and "hop in and steer"; Docker environments shared team-wide. | Cron-native scheduling verb; spectator/steer mode distinct from handoff. |
| **Terragon** (shut down 2026, [OSS](https://github.com/terragon-labs/terragon-oss)) | Agent-agnostic orchestrator over Claude Code/Codex/Amp/Gemini. | Provider abstraction; @-mention from Slack/GitHub; `terry` CLI takeover; an **MCP server** so other tools create tasks. | Task-creation as an MCP server. Cautionary: wrapping others' CLIs was a fragile position. |
| **Ona** (ex-Gitpod, acquired by OpenAI 2026, [docs](https://ona.com/docs)) | "Mission control for a personal team of SWE agents", governed. | **Auto-generated Dev Container + automations** from repo inspection; automations on PR events/schedules/webhooks as first-class objects; runs in your VPC with SSO/audit. | Self-configuring sandbox; governance as product. |
| **OpenHands** ([sdk](https://docs.openhands.dev/sdk)) | The open SDK for building coding agents — "Linux of coding agents". | REST agent server + WebSocket; OpenAI-compatible endpoint; explicit tiering — multi-agent reserved for the largest task class. | Being a library others embed. |
| **Sculptor** (Imbue, [docs](https://docs.imbue.com/features/features)) | Parallel Claude Code agents in Docker with low-friction git sync. | **Pairing mode**: one click merges a running agent's container work into your local checkout to test in your IDE, then diverge again; sessions persist plans + chats + tool calls + diffs together; BYO Anthropic auth. | Reversible container↔host sync; "revisit an abandoned experiment" as one replayable object. |
| **Amp** (Sourcegraph, [manual](https://ampcode.com/manual)) | Threads are shareable team-visible artifacts by default. | Threads sync + share by default; **`@thread-id`** pulls another thread in as context; **the Oracle** — a sub-agent on a *different vendor's* model, `amp.ai.ask()`, for second opinions. | Thread-to-thread composition; cross-model second opinion as a tool call. Closest kin to "the thread IS the record". |
| **GitHub Copilot coding agent** ([docs](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent)) | The agent is an assignee on an Issue; minimal new surface. | Assign the issue; **every step is a commit** in the Actions log; **structural branch fencing** — pushes only to `copilot/*`, can never approve/merge its own PR; hard **59-minute** session ceiling; cost = Actions minutes + AI credits. | Governance as platform capability, not policy; wall-clock cap as a designed constraint. |
| **Factory Droids** ([subagents](https://docs.factory.ai/harness/subagents)) | Enterprise terminal agent with a staged-scale story. | **Spec Mode** as a discrete mode producing a plan artifact; **Missions** bundle decomposition + dispatch + validation into one object; mid-session vendor swap via BYOK. | Mission as a scale unit (fan-out) vs. Tlön's sequential stage machine. |
| **Conductor** ([docs](https://docs.conductor.build/)) | Dashboard around "task = worktree + branch + terminal + diff + review". | Worktree per task by construction (convergent with Tlön); Conductor Cloud microVMs; review → PR → merge → **archive the workspace** as one flow. | "Archive" as a lifecycle action; a grid over several CLIs at once. |

Also noted, not profiled: **Google Antigravity 2.0** (Manager view over parallel agents; "Managed Agents" per-call isolated Linux — [I/O 2026](https://blog.google/innovation-and-ai/technology/developers-tools/google-io-2026-developer-highlights/)); **Replit Agent 3** (a user-facing **Autonomy Level** dial up to 200 min; self-testing in a browser; agents that build agents — [blog](https://replit.com/blog/introducing-agent-3-our-most-autonomous-agent-yet)); **Coder Agent Relay** (self-hosted governed execution for Claude Code in regulated enterprises — [2026-09-15](https://www.globenewswire.com/news-release/2026/09/15/3362210/0/en/coder-brings-claude-code-to-agent-relay-unlocking-agentic-development-for-the-world-s-most-regulated-enterprises.html)).

### Mechanism matrix

| Mechanism | Codex | Cursor | CC web | CC teams | Devin | Jules | Oz | Terragon | Ona | OpenHands | Sculptor | Amp | Copilot | Factory | Conductor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Durable record | session log | PR+attachments | session (share link) | mailbox, deleted at end | session + Knowledge | session | share link | task/branch | session | n/a (SDK) | plan+chat+tools+diff | **thread, cross-linkable** | commits + Actions log | Mission log | session |
| Git | PR | PR+branch | branch, PR, teleport, webhook auto-fix | none | PR, `/devin review` | branch+PR | via API | checkpointed commits | Dev Container auto-config | n/a | **pairing-mode sync** | loose | **fenced `copilot/*`, commit-per-step** | branch, PR | **worktree/task** |
| Context | repo in container | repo+deps+secrets | CLAUDE.md/MCP/skills | same, no shared history | **Knowledge + Playbooks** | full repo + plan | Docker env | checkout | auto-generated config | pluggable | container | AGENT.md + **`@thread-id`** | repo + code search | AGENTS.md + Spec Mode | per worktree |
| Cost | credit pool, 5h window | – | org rate limits | per-teammate tokens | seat | – | AI + compute | OSS | enterprise | OSS | free beta, BYO | usage | Actions min + credits | BYOK | microVM usage |
| Attention | task status | PR review | idle-until-teleport | `TeammateIdle` hook | confidence-flagged review | **browser push** | "hop in" link | @-mention | webhook automations | – | reopen | – | PR request | milestone flags | diff badge |
| Sandbox | container | VM | managed/self-hosted VM | parent session | VM | VM | Docker, shared | container | your VPC | your infra | local Docker | client-side | Actions VM | terminal/CI | microVM |
| Review | PR diff | PR + video/log | inline comments, auto-fix | self-review | **severity-labeled findings** | diff before PR | – | – | – | – | pairing → local IDE | – | human required, no self-merge | Mission validation | diff before PR |
| Resume | reopen | reopen | **`--teleport`** | none in-process | continuation | reopen | link | `terry` takeover | reopen | – | reopen saved | cross-device sync | reopen | reopen | reopen |
| Scheduling | – | – | **Routines** (cron/webhook/API) | – | – | API triggers | **`oz schedule --cron`** | @-mention | PR/schedule/webhook | primitive | – | – | issue assignment | – | – |

### Field baseline (table stakes)

1. **Isolated per-task sandbox** preloaded with the repo — universal.
2. **PR as the unit of delivered work.**
3. **Plan-before-code as an offered, often default, gate** (Jules mandatory, Factory Spec Mode, Claude plan mode, Devin Playbooks).
4. **Human review before merge, structurally enforced in several** (Copilot can't self-merge).
5. **A repo-level conventions file** (AGENTS.md / CLAUDE.md) as a cross-vendor standard.
6. **Parallel execution as marketing**, not a differentiator.
7. **Usage tied to a rate-limited tier or credits, pooled across surfaces** — Tlön's bucket framing at bigger scale.
8. **A needs-you signal** (push, Slack, PR comment, badge) as assumed infrastructure.

### Genuinely novel — steal candidates

- **Devin's Knowledge / Playbooks split** — Tlön's FACTS are Knowledge-shaped; Tlön has nothing Playbook-shaped (a named procedure with success criteria a coworker can be told to run). The workline stage playbooks are the seed.
- **Claude Code's hook-enforced task gates** (exit 2 = block + feedback) — deterministic policy around state transitions, independent of the model. Worklines' owed artifacts could get the same non-bypassable teeth.
- **Amp's `@thread-id`** — a thread cites another thread's FACTS instead of sitting as inert history.
- **Amp's Oracle** — cross-model second opinion as one tool call; cheap: an MCP tool that asks the *other* bucket.
- **Sculptor's pairing mode** — reversible worktree↔checkout sync instead of one-shot "here's your diff".
- **Warp Oz's cron as a CLI verb** + per-unit fan-out — the template for the Oban layer's semantics.
- **Copilot's structural branch fencing** — a coworker's commits can only land on its own thread branch; a hook, not a request.

### What a one-person local system can't do and shouldn't try

Fleet-scale VM provisioning; team-wide thread visibility as an adoption mechanism (surveillance of yourself); enterprise governance surface (the audit that matters is `git log`); chat-ops/ticket intake as a primary interface (nobody is on the other end); cross-vendor provider abstraction as a business (Terragon's shutdown); a public SDK for third parties; marketed autonomy dials (trust-building for strangers).

## 3 · Frameworks, protocols, memory

_pending — survey running._

## 4 · Synthesis — adopt · keep · skip

_pending — written once §2–§3 land._
