# pi ecosystem synthesis — roadmap

*2026-08-17. Design/roadmap doc. Product of three read-only spikes over funes, manos, and
aleph, triggered by a sweep of the pi.dev package catalog. The question behind it: of the
extensions Andrew found, what should we **add**, what should we **steal** (build natively),
and what should we **borrow as a pattern** — then make it cohere with the existing stack.*

## The frame

Andrew's stack already out-builds most of the catalog: **funes** (memory/dossier + the
sovereign channel), **manos** (LSP sidecar, footer, format/consult/reload tools), **aleph**
(the TUI cockpit — embedded ghostty terminals, arbiter, panel system). So the value in the
catalog is mostly **ideas**, not code. This roadmap turns the good ideas into native work on
the existing spines, and parks the rest as a backlog.

### Already wired (declarative, in the flake — done)

`settings.json`'s `.packages` now carries, via the jq-merge activation:
`pi-mcp-adapter`, `pi-sandbox`, `@ollama/pi-web-search`, `pi-agent-browser-native`,
`pi-multi-account` (Anthropic OAuth + cap-aware failover; **anthropic-first** order so we
lean on the $100 Claude plan and fall over to ollama only on cap), `@gotgenes/pi-permission-system`,
`pi-cc-header`, `@lincoln504/pi-research`, `pi-interactive-shell`, `@narumitw/pi-retry`.
Owned config: `~/.pi/agent/provider-failover.json`. These are bolt-ons; everything below is
native work.

## The three native builds (spike findings)

### 1. Habits-axis in funes — effort **M**

A third memory axis beside FACTS (memory) and skills (procedures): **HABITS** — "how the
agent should work with Andrew," *agent-proposed, human-approved*. Distinct from a stated
`Fact kind=constraint provenance=stated` (Andrew's verbatim rule) by its provenance: a
`derived` claim promoted through an approval gate.

The funes dossier is real Ecto/SQLite, and the lane pattern is fully cookie-cuttered — every
lane is a table + schema + context fn + MCP tool + brief renderer + aleph panel section, each
shipped in a single commit historically (`question`, `todo`). Closed sets live as inline DB
`CHECK` constraints, not in the schema (widening = a migration, by design). Completion-time
columns (`approved_at`) present from birth.

**Integration points** (concrete):
- New migration `priv/repo/migrations/…_habit.exs` (`CREATE TABLE habit`, FK, `state CHECK
  (state IN ('pending','approved','rejected'))`, `approved_at`, index on `thread_id`).
- New `lib/funes/habit.ex` (mirror `question.ex`: `propose_changeset` + `approve_changeset`).
- `lib/funes/dossier.ex`: `propose_habit/1`, `approve_habit/1`, `reject_habit/1`, reads
  (`pending_habits_for_thread/1` and/or machine-wide `approved_habits/0` à la
  `always_loaded_constraints/0`).
- `lib/funes/bus.ex`: add `:habit_proposed`/`:habit_approved`/`:habit_rejected` to the
  broadcast allowlist guard.
- `lib/funes/board.ex`: add `habits:` to `in_scope/1`.
- `lib/funes/mcp/brief.ex`: `"habits" =>` in `scope/1` + a `habit/1` renderer.
- `lib/funes/mcp/tool.ex` + `server.ex`: `Tool.ProposeHabit` (agent-facing), registered.
  If machine-wide, also `Resource.Habits` (mirror `Resource.Constraints`, loaded per session).
- `aleph/panel/dossier.ex`: a `section("HABITS", …)` line (pending vs approved rendered
  distinctly — "a cut without a count lies").
- `aleph/cockpit.ex`: operator-gated approve/reject action + keybinding → `Dossier.approve_habit/1`
  (carry the real `:operator` identity, not `"aleph"`).

**Open decisions:** (a) **machine-wide vs thread-scoped** — "how to work with Andrew" reads
machine-wide (nullable `thread_id`, served like constraints); settle first. (b) **new `habit`
table vs an approval axis on `Fact`** — new table keeps boundaries clean (codebase preference)
despite semantic overlap with constraints. (c) approval identity must be the operator gate or
it's meaningless.

### 2. Cache + context observability in the footer — effort **S**

The footer already iterates every `AssistantMessage.usage`; the full cache breakdown
(`cacheRead`, `cacheWrite`, `cacheWrite1h`, `cost.{cacheRead,cacheWrite}`) is present and
unused. `getContextUsage()` gives window % for free. Ties directly to the
`2026-08-16-context-reuse-cribs.md` cache work.

**Scope (v1):** add to `manos/footer` a cache readout (read/write tokens, $ waste) and keep
the context bar; re-derive cache-miss detection locally (pi's `detectCacheMiss`/`computeCacheWaste`
helpers exist but aren't publicly exported — raw inputs are all present, so it's friction, not
a wall). **Boundary:** footer stays funes-free (it's the generic package that loads for every
pi); no funes coupling here.

### 3. LSP blast-radius / impact tool in manos — effort **S/M**

The `manos/lsp` + `manos/lspd` sidecar already ships `references` and `symbols` (document-scoped)
as pi tools over a warm server pool. Impact analysis is pure orchestration over those two
primitives — no ast-grep, no persistent graph, no new subprocess:

1. Parse `git diff` → changed files + hunk line ranges (net-new, trivial).
2. Map ranges → symbols via `documentSymbol` (range-containment).
3. `references()` at each touched symbol's def → first-order blast radius; bounded BFS for
   transitive (dedup by symbol, cap depth).

**Scope (v1):** an `impact(diff_ref?)` tool, depth-1 first. A `repo_map(dir?)` sketch (top-level
symbols per file/dir via `git ls-files` + `documentSymbol`) is a **M** follow-on. An
edge-bearing call-graph is **L** — that's the pi-fovea reimplementation we explicitly avoid.

**Where it lives:** extend `manos/lspd` (reuse the warm pool) + register new tools in
`manos/lsp/src/extension.ts`. The one shared-seam risk: widening `codec.ts`'s closed method
union + `{path,line,col}` params shape to carry structured symbol/reference returns — touches
both packages; the design doc treats this codec as "the seam that must not drift."

**Risks:** LSP `references` quality is effectively **Elixir (Expert) + TS only**; `nil`/bash/json
give weak cross-file refs. Whole-repo maps warm/index the whole project (needs concurrency
limits + caching). `references` is name-binding, not a sound call graph — Elixir macros/dynamic
dispatch under-report; frame impact as an approximation. Saved-state only (no `didChange`) —
fine for a `git diff`-driven tool.

## The tabbed observability panel (Andrew's direction)

Usage **becomes an aleph panel**, and the panel gains **tabbed sections** to flip through:
**[Usage · Cache · Context]**. The spike confirms this is the *right* home — provider usage
can't live in pi's in-process footer (no quota API; ollama.com usage is entirely outside pi).

**Data path — reuse the funes→aleph pipe, no new IPC:** the funes-aware `manos/pi` extension
(not the generic footer) emits per-turn telemetry (cache/context/usage) into funes; aleph's
panel renders it off the existing PubSub topic, exactly as `panel/dossier.ex` renders the board.
- **Usage tab:** Anthropic caps parsed from `after_provider_response` headers in `manos/pi`
  (brittle, provider-specific — isolate the parser); ollama.com usage via the existing
  `ollama:usage` endpoint (mirrors `@entelligentsia/pi-ollama-cloud-usage-tracker`, which we do
  **not** install — the tracking already exists).
- **Cache/Context tabs:** the same numbers the footer computes, mirrored into the panel via the
  telemetry channel for the cross-session view.

**Reusable infra:** build **generic tab support** into aleph's panel/spaces system (a panel
slot that cycles sub-views), not a one-off — every panel can benefit. Effort **M–L**, gated on
slices 1–2 settling the telemetry shape.

**Open decision:** does per-turn telemetry **persist** in funes (a new lightweight lane/table)
or stream **ephemerally** over the Bus? Lean ephemeral for cache/context (cheap, live), persist
only what's worth history (usage-over-time).

## Recommended sequence

1. **Footer: cache-miss/waste + context% (S)** — zero blockers, fastest value, warms the
   telemetry data-shapes the panel will reuse.
2. **Habits-axis in funes (M)** — the "works like your brain" core; self-contained vertical slice.
3. **LSP blast-radius/impact tool (S/M)** — reuses shipped primitives; high code-work lever.
4. **Tabbed observability panel + usage (M–L)** — reusable aleph tab infra; funes-fed; the
   riskiest (cross-process, brittle provider headers) last, once telemetry shapes are settled.

## Backlog — patterns to borrow (not scheduled)

- **Per-project capability profiles** (from `@piagent/platform`) → folds into
  `2026-08-17-pi-coworker-profiles-design.md` (frontend/backend capability locks per Tlön profile).
- **Per-role model-routing profiles** (from `pi-maestro-teammate`) → your routing is manual
  `mise pi:*`; a role→model map is the idea, not the DAG engine (aleph arbiter already spawns).
- **Source-packet → synthesis-page ingestion** (from `@zosmaai/pi-llm-wiki`) → a funes ingestion
  path for URLs/PDFs into structured, linked facts; pairs with `@lincoln504/pi-research` output.
- **Notify-on-event** (from `@aliou/pi-processes` / pi-interactive-shell Monitor mode) → the
  `herdr-native-notifications` "agent waiting on you" want (OSC 9/777 via ghostty). PARTIAL:
  `@pi-unipi/notify` is now installed (notify-send-based, `agent_settled`/`ask_user_prompt`/
  `permission_request`) — a pragmatic stopgap, not yet the zero-dep OSC-through-ghostty path.
- **Recurring-tasks Space** (concept from `pi-schedule`, not the extension) → a new `Aleph.Space`
  with a Borgesian name, Oban-backed — the recurring/scheduled-tasks lens already mused in the
  funes/aleph notes. Its own panel(s) over an Oban job table.
- **Session-deck / monitor** (ideas from `@robhowley/pi-session-deck`) → feeds the deferred
  observability panel (below): a live session/monitor readout in the cockpit.
- **Mobile / remote session access** (from `@firstpick/pi-package-webui`) → the one thing aleph's
  terminal hub doesn't cover; a real gap, not a duplicate.
- **Inline image rendering** (from `pi-pretty`) → relevant to the minimax-m3 `/consult` vision flow.

## Build status (2026-08-17)

- **Slice 1 — footer cache/context — DONE** (`2577a52`). `accumulateUsage` + `cacheHitPct`; a
  `↺N%` cache-reuse readout in the footer, shown only when caching is in play. 9 tests, tsc clean.
- **Slice 2 — habits axis in funes — DONE** (`061b43b`). `habit` table + schema, Dossier
  propose/approve/reject + approved/pending reads, `propose_habit` MCP tool, `Resource.Habits`
  (`funes://habits`), Bus `:habit_*` events. Machine-wide, agent-proposed / operator-approved.
  199 funes tests, compile clean w/ `--warnings-as-errors`.
- **Slice 3 — LSP blast-radius — DONE** (`aa87360`). `impact` pi tool: git diff → touched symbols
  → external callers, first-order. Additive codec widening; pure `parseDiff`/`rangesOverlap`
  unit-pinned. lspd 37 + lsp 4 tests, tsc clean. Elixir+TS coverage.
- **Slice 4 — habits review panel — DONE** (`a4f08c4`). `Aleph.Panel.Habits` on Tlön (right),
  live on `funes:habits`. Completes slice 2's loop (pending queue visible). 194 aleph tests,
  compile clean. On-screen paint + in-TUI approve are the eye-test / a fast-follow.

### Remaining (needs a decision or the human's live aleph)
- **Slice 5 — tabbed observability panel (usage/cache/context).** Blocked on the telemetry-path
  decision: pi's in-process cache/context can't reach the Elixir cockpit without a bridge, and
  funes is the wrong home for per-turn metrics (it's memory/comms, not a metrics store). Options:
  (a) a new `post_telemetry` MCP tool → funes broadcasts ephemerally (no persistence) → panel;
  (b) aleph polls provider endpoints directly for USAGE only (ollama.com works; Anthropic has no
  public quota API), leaving cache/context to the footer. Recommend (b) for usage + keep
  cache/context in the footer, revisiting (a) only if a cross-session cache view earns its keep.
- **In-TUI habit approve** — a cockpit `pick`/key action emitting `{:approve_habit, id}`; needs
  live-aleph verification, so held for the human.

## Explicitly out of scope / not taken

Duplicates of the existing spine, skipped: `@misunders2d/agentnet` (= funes), `@nklisch/pi-plugins`
(forked mcp-adapter would fight the funes channel), `pi-vault-mind`/`pi-llm-wiki` as installs (=
funes memory), `pi-maestro-teammate`/`pi-fovea` as installs (= aleph/manos reinvented — steal the
ideas, above). Pretty-output libs (`pix-pretty`, `pi-pretty`) risk fighting manos tool output —
only the inline-image idea is worth borrowing.
