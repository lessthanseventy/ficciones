# pi extension prior art — a survey for a manos/funes extension

_Survey date: 2026-08-16. Scope: the pi coding-agent extension ecosystem (pi.dev, ≈5,374 packages, ~1,000+ extensions) mined for cribbable prior art for `modules/manos/pi/`. Focus is the **pi extension API surface** (the highest-value extract) and the extensions most relevant to funes/manos's goals._

**What manos/pi is today** (baseline for every recommendation below): a 3-hook adapter that makes a pi session a funes citizen. It uses `session_start` (register + claim pane), `before_agent_start` (fetch `get_dossier`, inject a rendered brief as a `customType: "funes-brief"` message), and `turn_end` (refresh a footer widget). It hand-rolls a ~150-line MCP-over-StreamableHTTP client (`mcp.ts`) for its own two internal calls (`register`, `get_dossier`), and — per the comment in `extension.ts` — the **model-facing** funes tools reach the model through a *separate* `pi-mcp-adapter` connection on the same bearer token. The adapter holds no state and reads identity from `FUNES_*` env vars only.

The headline finding: **manos uses ~3 of ~30 lifecycle hooks and none of `registerTool` / `renderCall` / `registerMessageRenderer` / `ctx.ui.select`.** A real tool-invoke + rich-rendering API exists and is well documented. Most of the value below is unlocking it.

---

## 1. The pi extension API, as actually documented

Sources: [`packages/coding-agent/docs/extensions.md`](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) (canonical, fetched in full), [DeepWiki: Extension API & Lifecycle Events](https://deepwiki.com/earendil-works/pi/6.1-extension-api-and-lifecycle-events), [`docs/sdk.md`](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md), [examples/extensions](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions). The repo is mirrored at `badlogic/pi-mono` and `hochej/pi-mono`.

An extension is a TS module exporting `export default function (pi: ExtensionAPI) { … }` (sync or async), auto-discovered from `~/.pi/agent/extensions/*.ts` or `.pi/extensions/*.ts`, or declared in `package.json` `"pi": { "extensions": [...] }` (which is how manos ships) or `settings.json` `"packages": ["npm:…", "git:…"]`. Loaded via `jiti`, so TS runs uncompiled.

### 1a. Lifecycle events (`pi.on(name, handler)`)

manos uses only the three marked **[USED]**. The rest are the surface it is leaving on the table.

| Event | Fires | Can… | Relevance to funes |
|---|---|---|---|
| `project_trust` | before pi trusts a project | return `{trusted}` | — |
| **`session_start`** [USED] | session begins/reload/resume/fork | side effects; `event.reason` | register/claim pane ✔ |
| `session_shutdown` | before teardown; `event.reason` | clean up | **`close_thread` / deregister on quit** (not done today) |
| `resources_discover` | resource scan | contribute skill/prompt/theme paths | ship funes skills/prompts |
| `session_info_changed` | `/name` change | — | mirror thread name → funes |
| `session_before_switch`/`_fork` | before switch/fork | `{cancel:true}` | open child thread on fork |
| **`before_agent_start`** [USED] | after prompt submit, before loop | inject `message`, rewrite `systemPrompt` | inject the brief ✔ |
| `agent_start`/`agent_end`/`agent_settled` | agent run lifecycle | — | bank "work since" on settle |
| **`turn_end`** [USED] / `turn_start` | each LLM+tool cycle | — | footer refresh ✔ |
| `message_start`/`_update`/`_end` | streaming message lifecycle | — | — |
| `tool_call` | **before** a tool runs | **`{block:true, reason, terminate}`** | policy gate; observe funes-relevant calls |
| `tool_result` | **after** a tool runs | **modify `content`/`details`/`isError`** | **auto-`record_check` from test-command results** |
| `tool_execution_start/_update/_end` | fine-grained exec | — | — |
| `input` | user input, pre-skill-expansion | `{action:"continue"\|"transform"\|"handled", text}` | intercept `/`-less funes verbs |
| `user_bash` | user runs `!`/`!!` | intercept / return result | — |
| `context` | **before each LLM call**; deep-copied messages | return `{messages}` (non-destructive) | **refresh/inject dossier every call**, not just at agent start |
| `before_provider_headers` | after HTTP headers built | mutate `event.headers` in place | (the Claude-Code adapter's `headersHelper` analogue — funes tools ride MCP, so N/A here) |
| `before_provider_request` / `after_provider_response` | around provider call | replace payload / read status | — |
| `model_select` / `thinking_level_select` | model/thinking change | — | note model on thread (already shown in roster) |
| `session_before_compact`/`session_compact` | compaction | provide custom summary | **summarize into funes facts on compact** |
| `session_before_tree`/`session_tree` | tree nav | custom summary | — |

### 1b. Tool registration — the big miss

```ts
pi.registerTool({
  name, label, description,
  promptSnippet?, promptGuidelines?,     // how it appears in the system prompt
  parameters: TypeboxSchema,             // @sinclair/typebox
  prepareArguments?(args),               // compat shim before validation
  async execute(toolCallId, params, signal, onUpdate?, ctx?): Promise<ToolResult>,
  renderCall?(args, theme, renderContext): Component,        // pi-tui component
  renderResult?(result, {expanded,isPartial}, theme, ctx): Component,
  renderShell?: "self",
});
```

- `ToolResult` = `{ content: [{type:"text",text}], details?, isError?, usage?, terminate? }`. `details` carries arbitrary state for rendering.
- **Custom rendering** is real: `renderCall`/`renderResult` return `@earendil-works/pi-tui` components (Box, SelectList, BorderedLoader…) with theme colors, expand/collapse, `invalidate()` for rerender, streaming via `onUpdate`. This is what "rich funes tool rendering" would use.
- **Built-in overrides**: register a tool named `read`/`bash`/`edit`/`write`/`grep`/`find`/`ls` to replace it; omit renderers to inherit built-in rendering.
- **Dynamic tools**: `pi.getActiveTools()` / `pi.setActiveTools([…])` (additive), plus a search-tool pattern to load tools on demand.
- Output-truncation utilities are exported (`truncateHead/Tail/Line`, `DEFAULT_MAX_BYTES=50KB`, `DEFAULT_MAX_LINES=2000`).

### 1c. Rendering / input / UI surfaces

- **Message & entry renderers**: `pi.registerMessageRenderer(customType, renderer)`, `pi.registerEntryRenderer(customType, renderer)`, `pi.registerMarkdownTransformer(fn)`. **manos already tags its injected brief `customType: "funes-brief"`** — so a `registerMessageRenderer("funes-brief", …)` is a drop-in path to render the brief as a branded widget instead of plain markdown.
- **Dialogs** (`ctx.ui`): `select(title, options)`, `confirm(title, msg, {timeout})`, `input(prompt, placeholder)`, `editor(title, prefilled)`, `notify(msg, level)`, plus `custom(factory)` to mount a raw pi-tui component in an overlay. **This is the native ask-user-question substrate.**
- **Status/chrome**: `setStatus(key,text)` [USED], `setWidget(key,lines)` [USED], `setTitle`, `setFooter`/`setHeader` (custom components), `setWorkingMessage/Visible/Indicator`.
- **Slash commands**: `pi.registerCommand(name, {description, getArgumentCompletions?, handler})`; collisions auto-suffix (`/review:1`). `pi.registerShortcut(key, {handler})`, `pi.registerFlag`, `pi.registerProvider`/`unregisterProvider`.

### 1d. Message injection & state persistence

- `pi.sendMessage({customType, content, display, details}, {deliverAs:"steer"|"followUp"|"nextTurn", triggerTurn?})` and `pi.sendUserMessage(...)`. **`deliverAs:"steer"` can push a message into a *running* turn** — the mechanism for "another agent posted a blocker, steer it into this session" (funes-as-slack-for-agents).
- **Persistence**: `pi.appendEntry(customType, data)` writes a custom entry into the session JSONL (not sent to the LLM); on `session_start`, replay via `ctx.sessionManager.getEntries()`. This is how an extension survives reload/resume. manos currently persists nothing (identity from env only) — fine for a stateless adapter, but see §4.
- Session control from commands: `ctx.newSession/fork/switchSession/navigateTree/reload/waitForIdle`; labels via `pi.setLabel`, `pi.setSessionName`.
- `ctx.mode` is `"tui"|"rpc"|"json"|"print"`; `ctx.hasUI`. **The same UI calls work in RPC mode** (they emit JSON to a remote client) — relevant to aleph driving pi over a wire.

**Flag for manos**: the hand-declared `pi.ts` shim (setStatus/setWidget/notify + 3 events) is a faithful but tiny slice. The real `@earendil-works/pi-coding-agent` types expose everything above. Nothing manos relies on is wrong; it is just narrow.

---

## 2. Survey table — the most relevant extensions

Downloads are monthly, from `pi.dev/packages?type=extension` (page 1, 2026-08-16). Repos from the npm registry.

| Name | install id | dl/mo | repo | what it does |
|---|---|---|---|---|
| pi-mcp-adapter | `npm:pi-mcp-adapter` | 354K | nicobailon/pi-mcp-adapter | MCP client as one ~200-tok proxy tool; lazy servers, OAuth/bearer, elicitation→dialogs, per-tool approval |
| pi-web-access | `npm:pi-web-access` | 258K | nicobailon/pi-web-access | web search / URL fetch / GitHub clone / PDF / YouTube; many search providers |
| @vigolium/piolium | `npm:@vigolium/piolium` | 231K | vigolium/piolium | 17-phase security audit via specialist sub-agents, resumable `audit-state.json` |
| @juicesharp/rpiv-ask-user-question | `npm:@juicesharp/rpiv-ask-user-question` | 52K | juicesharp/rpiv-mono | one `ask_user_question` tool; tabbed typed-option questionnaire w/ previews+notes |
| @juicesharp/rpiv-todo | `npm:@juicesharp/rpiv-todo` | 47K | juicesharp/rpiv-mono | model's todo list as a live overlay |
| pi-lens | `npm:pi-lens` | 41K | — | real-time LSP/linter/formatter/type-check feedback |
| @tintinweb/pi-subagents | `npm:@tintinweb/pi-subagents` | 40K | tintinweb/pi-subagents | Claude-Code-style subagents; `.md`+frontmatter agents, `Agent` tool, croner schedule |
| pi-fabric | `npm:pi-fabric` | 33K | monotykamary/pi-fabric | programmable tool + agent runtime |
| @ff-labs/pi-fff | `npm:@ff-labs/pi-fff` | 33K | — | fuzzy file/content search |
| pi-goal-list-loop-audit | `npm:pi-goal-list-loop-audit` | 32K | DraconDev/pi-goal-list-loop-audit | goal interviews + audited forever-loops; **detached evidence-quoting auditor** |
| pi-simplify | `npm:pi-simplify` | 31K | — | reviews changed code for clarity/consistency |
| @narumitw/pi-goal | `npm:@narumitw/pi-goal` | 30K | narumiruna/pi-extensions | autonomous `/goal` completion |
| @gotgenes/pi-permission-system | `npm:@gotgenes/pi-permission-system` | 27K | gotgenes/pi-packages | permission enforcement (tool_call gating) |
| pi-background-tasks | `npm:pi-background-tasks` | 27K | ismailsaleekh/pi-background-tasks | durable background shell tasks + read-only delegated agents |
| pi-hermes-memory | `npm:pi-hermes-memory` | 25K | chandra447/pi-hermes-memory | persistent memory, SQLite FTS5 session search, secret scanning |
| @mjasnikovs/pi-task | `npm:@mjasnikovs/pi-task` | 23K | mjasnikovs/pi-task | crash-safe `/task` pipelines with verify/enforce gates + remote web view |
| @narumitw/pi-plan-mode | `npm:@narumitw/pi-plan-mode` | 19K | narumiruna/pi-extensions | Codex-like read-only `/plan` mode |
| pi-powerline-footer | `npm:pi-powerline-footer` | 18K | — | powerline status bar |
| @quintinshaw/pi-dynamic-workflows | `npm:@quintinshaw/pi-dynamic-workflows` | (sidebar) | QuintinShaw/pi-dynamic-workflows | JS-VM workflow orchestration: `agent()/parallel()/pipeline()/phase()`, resume, worktrees, `/workflows` TUI |
| @zhcsyncer/pi-tool-display-intent | `npm:@zhcsyncer/pi-tool-display-intent` | (sidebar) | zhcsyncer/pi-extensions | intent-aware compact tool rendering, adaptive diffs, output compaction |
| @zhcsyncer/pi-glance | `npm:@zhcsyncer/pi-glance` | (sidebar) | zhcsyncer/pi-extensions | polished input surface, composable statuses, context-progress bar |
| @narumitw/pi-lsp | `npm:@narumitw/pi-lsp` | 16K | narumiruna/pi-extensions | language-agnostic LSP tools |
| pi-readseek / pi-hashline-edit-pro | `npm:pi-readseek` | 16K | — | LINE:HASH-anchored file ops / structural nav |
| pi-cc-extensions | `npm:pi-cc-extensions` | 12K | minuque/pi-cc-extensions | Claude-Code-style UI suite, context inspection, agent/session references |
| @narumitw/pi-statusline | `npm:@narumitw/pi-statusline` | 12K | narumiruna/pi-extensions | information-rich statusline (footer replacement) |
| pi-ask-user | `npm:pi-ask-user` | 10K | edlsh/pi-ask-user | `ask_user` tool, searchable split-pane, multi-select + freeform |
| @danypops/pi-tickets | `npm:@danypops/pi-tickets` | 10K | — | GitHub/GitLab/Jira tickets daemon as tools |
| pi-interview | `npm:pi-interview` | 9K | nicobailon/pi-interview-tool | interactive interview form |
| pi-mcp-extension | `npm:pi-mcp-extension` | 9K | — | alternate MCP client extension |
| @gotgenes/pi-subagents | `npm:@gotgenes/pi-subagents` | 8K | gotgenes/pi-packages | subagent **core with typed API + lifecycle events other extensions build on** (fork of tintinweb) |
| @narumitw/pi-btw / pi-btw | `npm:@narumitw/pi-btw` | 11K | narumiruna/pi-extensions | `/btw` parallel side-question conversations |

_Not reached: `pi-hypa`, `pix-subagent`, `pi-autoresearch`, `pi-smart-router`, `pi-yaml-hooks`, `pi-loop`, `pi-research`, `pi-browser-use`, `pi-llm-wiki`, `nervous-system`, `pi-plugin`, `pi-pr-review`, `pi-autocommit`, `pi-extension-todo` — not on page 1 of the download-ranked list; names only, from the task brief. The `narumiruna/pi-extensions`, `zhcsyncer/pi-extensions`, and `gotgenes/pi-packages` monorepos each hold several of the above._

---

## 3. Deep dives (the cribbable ones)

### 3a. pi-mcp-adapter (nicobailon, 354K/mo) — the MCP bridge manos already leans on
Source: [README](https://github.com/nicobailon/pi-mcp-adapter), npm `pi-mcp-adapter@2.26.0`.
- **Design**: instead of N verbose tool schemas, exposes a **single `mcp()` proxy tool (~200 tokens)** with `search`/`describe`/call sub-modes; servers are **lazy** (connect on first call, idle-disconnect). Metadata caches to `~/.pi/agent/mcp-cache.json` so search works offline. `directTools: true|[names]` promotes chosen tools to first-class registered tools (~150–300 tokens each; warns past 75).
- **Transports**: stdio, StreamableHTTP+SSE fallback, unix socket; **bearer tokens and full OAuth 2.0** (auth-code, client-credentials, DCR), secrets via `"!command"` interpolation at connect time, stored in OS keyring (`@napi-rs/keyring`).
- **Rendering**: results render collapsed (title + first line + "Ctrl+O to expand"); output guard caps 50KiB/2000 lines, spills to temp files, caps `details.mcpResult` at 16KiB.
- **MCP-level**: **elicitation → pi `select`/`input` dialogs**, sampling (servers call pi models), prompts → `/mcp__<server>__<prompt>` slash commands, per-tool `approveTools` gates that fail-closed headless, brokered via a `MCP_TOOL_APPROVAL_REQUEST_EVENT`.
- **Deps**: heavy — `@modelcontextprotocol/{client,core,ext-apps}`, keyring, ajv, recheck, cross-spawn, smol-toml, zod.
- **Crib**: the **proxy-tool token-economy pattern** and **elicitation→dialog** bridge. But note the weight (§4a).

### 3b. @juicesharp/rpiv-ask-user-question (52K/mo) — the model asking *you*, typed
Source: [README](https://github.com/juicesharp/rpiv-mono/tree/main/packages/rpiv-ask-user-question), npm `@juicesharp/rpiv-ask-user-question@2.6.0` (deps: `typebox`, `@juicesharp/rpiv-config`).
- Registers one tool `ask_user_question`. Up to **4 questions in a tabbed dialog**; each question = **2–4 authored options, each with a description of what it means / what it costs**, single- or multi-select, plus a **"Type something." free-text row on every question**, an optional **markdown `preview`** (ASCII mockup / code / diagram) in a bordered box, and `n` to attach multiline notes.
- Keyboard: ↑/↓ browse, Tab between questions, Enter select, a Submit tab that reviews before returning; `Ctrl+]` collapses to show history. Answers return to the model as **structured data**.
- **Graceful degradation**: native dialogs in VS Code/Zed; in non-interactive runs it **removes the tool from the model's options** so the model can't hang waiting.
- **Crib**: this is the exact shape for the funes **UNKNOWNS/question** vocabulary — typed options + free text + preview, returned structured. (pi-ask-user [edlsh] and pi-interview [nicobailon] are simpler variants of the same idea: searchable split-pane multi-select, and a multi-field interview form.)

### 3c. @tintinweb/pi-subagents (40K/mo) — Claude-Code subagents, `.md`+frontmatter
Source: [repo](https://github.com/tintinweb/pi-subagents), npm `@tintinweb/pi-subagents@0.16.1` (deps: typebox, croner, nanoid). A **typed-API fork exists as `@gotgenes/pi-subagents`** ("core other extensions build on").
- **Agents are Markdown files with YAML frontmatter** discovered from `.pi/agents/<name>.md` → `.agents/agents/<name>.md` → `~/.pi/agent/agents/<name>.md`. Frontmatter: `name, description, tools (csv or * or ext: selectors), model (fuzzy+fallback), thinking, max_turns, allowed_subagents, prompt_mode: replace|append, isolation: worktree, memory: project|local|user`; body = system prompt.
- **Delegation via an `Agent` tool**: `{subagent_type, prompt, description, name?, model?, thinking?, max_turns?, run_in_background?, inherit_context?, isolation?, schedule?}`. Foreground blocks & returns inline; background returns an id and notifies (`<task-notification>` XML + styled boxes), transcripts to a tmp path.
- **Scheduling** via croner: 6-field cron / interval (`5m`) / relative one-shot (`+10m`) / absolute ISO; PID-locked at `.pi/subagent-schedules/<sessionId>.json`, reset on `/new`, restored on `/resume`.
- **Crib**: the **markdown-frontmatter agent definition** and **typed `Agent` tool schema** are the community-standard vocabulary. If funes/aleph ever exposes named roles to a pi session, matching this schema means pi users already know it. (aleph already owns spawn/topology, so take the *schema*, not the runtime — see §5.)

### 3d. @quintinshaw/pi-dynamic-workflows — deterministic fan-out orchestration
Source: [README](https://github.com/QuintinShaw/pi-dynamic-workflows), npm `@quintinshaw/pi-dynamic-workflows@3.6.0`.
- Pi writes a **deterministic JS workflow** using runtime globals `agent()`, `parallel()`, `pipeline()`, `phase()` with a `meta` export (`name, description, phases[]`). Runs in a **VM sandbox that blocks nondeterminism** (`Math.random()` etc.). Up to 16 concurrent / 1000 total subagents.
- **Model routing per agent** by tier (`small|medium|big`) or exact `provider/model:thinking`. **Real token+cost accounting** (`budget.spent()/remaining()`, phase/run budget gates). **Resume** via journal replay keyed by positional call index; `resumeFromRunId` re-runs only edited/new calls. `isolation:'worktree'` per agent. A `/workflows` TUI shows phases/agents/models/tok-per-sec with a syntax-highlighted transcript pager. Ships a real `/deep-research`.
- **Crib**: the **journal-replay resume keyed by call index**, **budget gates**, and the **`/workflows` TUI** as a model for a funes triage panel. The JS-VM engine itself is *not* a fit (§5).

### 3e. piolium (231K/mo) — phased pipeline with resumable file-state
Source: [README](https://github.com/vigolium/piolium), npm `@vigolium/piolium@0.0.13` (zero deps).
- **17 phases (P1–P17) in 5 stages** (recon→analysis→adversarial validation→PoC/report→cleanup). Resumable via `audit-state.json`. Findings flow candidate→`findings-draft/`→`findings/<id>-<slug>/{draft.md,report.md,poc}`→`final-audit-report.md`; durable `attack-surface/` knowledge base.
- **Crib**: the **on-disk phase state + draft→verified→final finding pipeline** is a clean template for a durable, resumable multi-step funes task — but the 17-phase security machinery itself is domain-specific (§5).

### 3f. pi-goal-list-loop-audit (32K/mo) — the detached, evidence-quoting auditor ⭐
Source: [README](https://github.com/DraconDev/pi-goal-list-loop-audit), npm `pi-goal-list-loop-audit@0.35.4`. **This is the closest philosophical match to funes' "measured verification" (record_check / CHECKS).**
- **Separates implementation from verification with an independent process.** On a completion claim, the main agent writes the claim to disk and returns; a **detached, extension-less auditor** then launches with only `read/grep/find/ls/bash` and **no parent context or APIs**, and verifies against the goal's `Done when:` contract.
- The **`regression_shield`** requires the auditor to **quote raw command output per verification-contract item**; "the orchestrator rejects evidence-free approvals." A second orchestrator-side gate revalidates. This is explicitly the anti-"bamboozle/self-certify" design.
- Goals are **interview-drafted** (agent proposes metrics/success criteria; a separate "Drafter" agent with its own thinking level; confirm-gate before activation; `/list` batches). State is **structured JSON in `.pi-glla/`** (active slot, waiting items, per-item audit trails, ledger). Three loop flavors (metric / metricless-spec / project-audit); **metric captured by the orchestrator, not self-reported.** Cross-session recovery via `.pi-glla/session-handoff.json` consumed on `session_start`; 15s heartbeat; bounded retry envelope with fallback-model chains.
- **Crib**: the **detached-auditor-quoting-raw-evidence** contract *is* funes' record_check thesis in agent form, and the **interview-to-contract goal drafting** maps to funes north_star + `Done when:` + UNKNOWNS. Steal the pattern, wire the evidence to funes CHECKS.

### 3g. zhcsyncer/pi-tool-display-intent + pi-glance — rendering polish
Source: [repo](https://github.com/zhcsyncer/pi-extensions), npm `@zhcsyncer/pi-tool-display-intent@0.8.0`, `@zhcsyncer/pi-glance@0.7.0`. READMEs are feature-list + screenshots and **do not disclose which hooks they use**; from the API surface they can only be `registerTool` renderers / `tool_result` / `setWidget`/`setFooter`/`setHeader` / `registerMessageRenderer`. Features worth noting: **model-written intent phrases on tool rows, collapsed/expanded ledgers, stable `done` rows, adaptive diffs, bounded bash previews** (display-intent); **composable statuses, working-tree counts in the git status line, `/diff` review, theme-aware working indicator** (glance). **Crib**: the *idea* of intent-labeled, collapsible tool rows and a context-progress footer — implement natively via `renderResult` + `setFooter`.

---

## 4. Recommended cribs for ficciones (prioritized)

Cross-referenced against what manos/pi already does. **P0 = highest leverage.**

**P0 — Render `funes-brief` richly (near-zero cost, immediate).** manos *already* injects the brief as `customType:"funes-brief"`. Add `pi.registerMessageRenderer("funes-brief", …)` returning a pi-tui `Box` that renders FACTS/UNKNOWNS/BLOCKERS/TODOS/CHECKS as a branded, collapsible widget with certainty markers as colored glyphs — instead of the current plain markdown. Zero new deps, uses the customType already in `brief.ts`/`extension.ts`. _Crib: §3g rendering; §1c._

**P0 — Answers (b): a real tool-invoke + rendering API exists.** `pi.registerTool` + `renderCall`/`renderResult` returning pi-tui components is exactly the "render funes tools richly" capability the code comments assumed absent ("there is no pi API to invoke a tool from a lifecycle hook"). That comment is right about *lifecycle hooks* but the model-facing path has full rich rendering. **Recommendation: register the curated funes tools natively** (`fact`, `todo`, `ask`, `blocker`, `record_check`, `open_thread`/`close_thread`, `roster`) with `execute()` that calls funes over the existing `mcp.ts` client, and `renderResult` that shows, e.g., a banked fact with its certainty marker or a ✓/✗ check. This gives named tools + honest rendering and, notably, **could drop the pi-mcp-adapter dependency for the model-facing surface** (see 4a).

**P0 — ask-user-question for the funes UNKNOWNS vocabulary (answers (c)).** Register a funes `ask` tool modeled on §3b: 2–4 typed options each with a cost/description, a free-text row, optional markdown preview, rendered via `ctx.ui.select`/`custom`. On answer: write the resolution back to funes (resolve the question, optionally bank a `stated` fact from the operator's reply). This closes the loop the UNKNOWNS slice opened — the model raises an UNKNOWN and can *resolve it interactively* instead of guessing. _Deps: typebox only, like rpiv._

**P1 — Auto-record CHECKS from `tool_result` (answers (d), and funes' verification thesis).** Add a `tool_result` hook: when the bash tool ran a recognized test/build command, call funes `record_check` with the real exit code + tail — so CHECKS get banked as measured truth **without the model having to remember to call record_check**. This is the ficciones-native version of §3f's orchestrator-captures-the-number principle. Pair with the §3f *detached-auditor* pattern if/when funes wants independent re-verification of a claimed completion.

**P1 — `/funes` slash commands + a triage panel for Tlön (answers (d)).** `pi.registerCommand("funes", …)` opening a `ctx.ui.select` / `custom` panel over open blockers/questions/todos — modeled on pi-mcp-adapter's `/mcp` panel and pi-dynamic-workflows' `/workflows` TUI. Sub-commands: `roster`, `dossier`, `ask`, `triage`. A `pi.registerShortcut` to pop the dossier. This is the pi-side surface for the Tlön/triage flow.

**P1 — `close_thread` on `session_shutdown`.** manos registers on start and supersedes zombies, but never deregisters. Add a `session_shutdown` handler that calls funes `close_thread`/deregister so quitting pi cleanly releases the pane, rather than leaving a zombie for the next register to supersede. _Crib: §1a; funes already has the verb (commit `open_thread`/`close_thread`)._

**P2 — Steer cross-thread messages into a running session.** Use `pi.sendMessage(..., {deliverAs:"steer"})` so a funes chatter message or a newly-filed blocker from another agent can be pushed into *this* live session mid-turn — the literal "slack for agents" delivery. Requires a lightweight poll or an SSE subscription on the funes channel; gate behind a setting.

**P2 — Persist thread binding via `appendEntry`.** Optional: `pi.appendEntry("funes-binding", {thread, token-ref})` and restore on `session_start`, so a `/resume`d session re-attaches to its funes thread even if the `FUNES_*` env is gone. Keeps the "adapter holds no state" spirit by persisting only the pointer, not funes data. _Only if resume-without-env is a real workflow._

**P3 — Adopt the `.pi/agents/<name>.md` frontmatter schema** (§3c) as the on-wire vocabulary *if* aleph/funes ever exposes named roles to pi, so pi users get a familiar surface. Schema only, not the runtime.

### 4a. Should we depend on pi-mcp-adapter instead of hand-rolling `mcp.ts`?

**Two distinct jobs — keep them separate:**
1. **The extension's own lifecycle calls** (`register`, `get_dossier`): **keep the hand-rolled `mcp.ts`.** It is ~150 lines, zero deps, and deliberately mirrors funes' proven e2e wire test (`server_test.exs`). Pulling in pi-mcp-adapter's 12-dep tree (keyring, ajv, recheck, cross-spawn…) to make two internal calls is the wrong trade. `mcp.ts` is correct as-is.
2. **The model-facing funes tools** (today via a separate pi-mcp-adapter connection): **prefer migrating these to native `registerTool`** (P0 above). Native gives rich `renderResult`, honest brief-style formatting, named tools in the system prompt, and **removes the external pi-mcp-adapter dependency entirely**. The only thing pi-mcp-adapter buys here that native doesn't is the ~200-token proxy economy and OAuth/elicitation plumbing — funes has a *small curated* tool set on a *static bearer*, so neither matters. **Verdict: don't adopt pi-mcp-adapter as a dependency; register funes tools natively and reuse `mcp.ts` inside their `execute()`.** (If funes ever needs to consume *third-party* MCP servers, pi-mcp-adapter is the right tool for that job — but that's a different requirement.)

---

## 5. What we would NOT steal (and why)

- **pi-mcp-adapter as manos's MCP client** — heavy deps (keyring/ajv/recheck/OAuth) for a job manos does in 150 dep-free lines against a static bearer. See §4a. (Its *patterns* — proxy economy, elicitation→dialog — are noted, not its bytes.)
- **pi-dynamic-workflows' JS-VM orchestration engine** (`agent()/parallel()/pipeline()`, 1000 subagents, VM sandbox) — aleph/funes already own thread topology and spawn; a second deterministic-JS orchestration universe would compete with, not complement, the arbiter model. Take its *resume-by-call-index* and *budget-gate* ideas only. Its per-agent model routing is also already covered by ficciones' `pi:*` mise tasks.
- **piolium's 17-phase security pipeline** — the phase machinery (P1–P17, threat modeling, PoC) is security-audit-specific; funes is coordination memory, not an auditor. Keep only the on-disk resumable phase-state shape (§3e).
- **pi-subagents' croner scheduler + Agent runtime** — aleph owns spawning; a per-session cron in the pi extension would duplicate that authority. Adopt the *agent-definition schema* only (§4, P3).
- **Cosmetic/peripheral extensions** — powerline/statusline/zentui, voice (`rpiv-voice`), telegram (`llblab/pi-telegram`), DeepSeek/Ollama-specific search & usage meters: out of scope for a coordination adapter. funes already renders its own footer/widget.
- **Third-party memory stacks** (pi-hermes-memory, pi-mentis, pi-goosedump) — funes *is* the memory of record here (SQLite-backed dossier); a parallel per-session memory would fork the source of truth, which is exactly the anti-laundering property `brief.ts` exists to protect.

---

## Sources
Core API: [extensions.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) · [DeepWiki 6.1](https://deepwiki.com/earendil-works/pi/6.1-extension-api-and-lifecycle-events) · [sdk.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md). Extensions: [pi-mcp-adapter](https://github.com/nicobailon/pi-mcp-adapter) · [rpiv-ask-user-question](https://github.com/juicesharp/rpiv-mono/tree/main/packages/rpiv-ask-user-question) · [pi-subagents](https://github.com/tintinweb/pi-subagents) · [pi-dynamic-workflows](https://github.com/QuintinShaw/pi-dynamic-workflows) · [piolium](https://github.com/vigolium/piolium) · [pi-goal-list-loop-audit](https://github.com/DraconDev/pi-goal-list-loop-audit) · [zhcsyncer/pi-extensions](https://github.com/zhcsyncer/pi-extensions) · [gotgenes/pi-packages](https://github.com/gotgenes/pi-packages). Download numbers: `pi.dev/packages?type=extension`, 2026-08-16. **Not reached**: npmjs.com HTML (403 — used registry.npmjs.org JSON instead); several sidebar packages (pi-hypa, pix-subagent, pi-smart-router, pi-yaml-hooks, pi-loop, nervous-system, etc.) not on page 1 of the ranked list.
