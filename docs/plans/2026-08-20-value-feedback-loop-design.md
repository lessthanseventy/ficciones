# Does this help? — a value / self-reflection loop for the aleph·funes system

Date: 2026-08-20
Status: design / living doc. Born from a 2026-08-20 conversation (operator + `claude-machine`) that
started as "are we just jerking off?" — i.e. can this system tell whether it's actually helping, or
only whether its code is correct. This doc logs what such a loop would need so we can build toward it.

## The problem, stated honestly

The system has **abundant correctness signal and near-zero value signal.**

- Correctness is cheap and everywhere: `mix precommit`, the test suite, the `verify` skill, types,
  the boundary compiler. All of it answers "does the code do what the code says."
- Value is expensive and answered by exactly one oracle — the operator — queried ad hoc, after the
  fact, and unsystematically.
- Worse than neutral: the process scaffolding (TDD, gates, task lists, red-green-refactor, the OMC
  delegation ceremony) **manufactures the sensation of rigor.** A well-executed low-value feature and
  a well-executed high-value one produce the identical green suite. The ceremony makes motion feel
  like progress. That is the failure mode this doc exists to catch.

Concrete tell from the day this was written: I built Tlön lazygit **Phase 5** (a settings modal),
verified it exhaustively, gate green — and could not answer whether anyone would ever open it. I
built the next *numbered* phase, not the most *valuable* thing, because a number is legible and value
is hard. The system had no way to notice that.

## What "working" actually means

Counterfactual utility: **does routing the operator's work through aleph·funes beat bare-terminal
Claude?** Decomposed into questions the system could in principle answer about itself:

1. **Landed?** Did a unit of work reach a commit / merge, or evaporate.
2. **Stuck?** Or was it reverted / re-touched / redone within N days. Reversion is the strongest
   negative signal there is, and it is free to observe (git).
3. **Right work?** Did it map to a stated priority (a flagged gap, a goal in the dossier) or was it
   numbered-phase / self-initiated momentum.
4. **Used?** Does what we ship ever get invoked after it ships. Today: **unmeasurable** — nothing logs it.
5. **Cheaper collaboration?** Fewer corrections, redirections, and takeovers per unit of work over time.

## The signal taxonomy — what to capture, cheapest first

### Tier 1 — Outcome signals (near-free, from git + funes)
- **Landing / stickiness** — commit reached; reverted or heavily re-touched within a window. Pure git.
- **Priority alignment** — was the work-unit tied to a stated goal/gap, or momentum. funes dossier /
  todos already hold the priority side; the missing half is tying a commit back to it.

### Tier 2 — Interaction signals (from conversation transcripts, captured continuously)
The richest *existing* corpus — Claude history — and today it is only ever read for content recall,
never graded for collaboration quality.
- **Correction rate** — frequency of "no / wrong / not what I meant / redirect" per unit of work, and
  the recurring *kind* (over-built, wrong direction, ignored a constraint, added slop, didn't verify).
- **Takeover rate** — "I'll do it myself" — the work the system did NOT help with.
- **Question quality** — did Claude ask the right clarifying question up front, or charge off and get
  redirected. (Front-loaded good questions correlate with work that sticks.)
- **Sentiment trajectory** — praise → frustration within a session.

### Tier 3 — Usage signals (MISSING — the single biggest gap)
- Does a shipped affordance — a modal, a verb, a keybinding, a skill, an MCP tool — ever *fire* after
  it ships. Without this, feature-value is permanently unmeasurable and "dead features" accumulate
  invisibly.
- Requires a lightweight **event log in aleph** (and ideally the Claude harness): append-only
  "affordance X invoked at T", no content, no PII — just which surfaces get used. Feeds a recurring
  "what did we build that nobody touches" report.

## The loop (the "automagical" part)

- **Capture continuously**: Tiers 1–2 as side-effects of normal operation; Tier 3 once instrumented.
- **Reflect on a cadence** — a recurring funes task (the mooted recurring-tasks/Oban space is the
  natural home) that, weekly:
  1. Revisits recent work-units; grades stickiness (git) and usage (telemetry).
  2. Tallies correction / takeover / sentiment from the week's transcripts.
  3. Writes a **graded outcome-memory per work-unit** — funes already has the `record_check` / CHECKS
     seam (measured verification); this extends it from "did it pass" to "did it help."
  4. Surfaces three lists: **dead features**, **high-correction task types**, **priority drift.**
- Over time this becomes a **dataset**, not a vibe: "work of kind K, done this way, stuck P% / got used
  Q%." That is the thing that lets the system *self-improve* instead of only self-execute — and lets me
  calibrate what to even propose next.

## What I'd need to build it (the literal ask: log what's missing)

1. **Usage telemetry in aleph** — highest leverage, smallest piece. An affordance-invocation event log.
2. **A work-unit ledger** — durable link {task/commit} → {stated priority} → {later outcome verdict}.
   funes dossier + CHECKS is the seam; needs the outcome-grading pass on top.
3. **A scheduled transcript-mining synthesizer** — episodic-memory is the read tool; this needs a
   *recurring* pass that extracts Tier-2 signal, not a one-off search.
4. **A baseline** — the operator's pre-system convos characterized once, as the counterfactual bar
   ("before the system, what did he reach for / correct / take over"). (First pass underway.)
5. **A cheap human check-in** — not eliminate the oracle, *lower its frequency and raise its signal*:
   a periodic "these N things shipped — used / not / worth it?" ping instead of ad hoc doubt.

## Anti-goals / risks

- **Don't let the loop become more ceremony** — it must be cheap and mostly automatic, or it becomes
  the exact false-rigor it diagnoses.
- **Don't over-instrument / surveil** — local, affordance-level, no conversation content.
- **Vanity metrics are the enemy** — "tests written", "commits", "phases shipped" are motion. Grade
  stickiness + usage, never activity.

## Lead direction: a native coordination plugin (replace the borrowed brains)

Surfaced by the operator 2026-08-20 ("maybe I need to write my own claude plugin … hand off to a
review coworker, not superpowers") and confirmed hard by the config audit below. This is the
**first-order move**, ahead of the telemetry pieces, because it removes false-rigor *and* wires the
loop at the source.

The problem in one sentence: **Claude-under-aleph is currently driven by three competing coordination
layers** — OMC ("delegate to `executor`"), superpowers ("dispatch the `code-reviewer` subagent"), and
funes ("hand off to a coworker on a thread"). The first two spawn **ephemeral subagents with no memory,
no thread presence, and no trace** — so their work is invisible to the very loop this doc designs. A
review that doesn't land in funes is a review the system can't learn from.

A bespoke plugin makes Claude-under-aleph:
- **Hand off to funes coworkers, not ephemeral subagents** — review / explore / execute land on threads
  as named peers (`@reviewer-machine`), their output durable + mineable, accumulating across runs.
- **Use funes memory, not the parallel `.claude/memory` duplicate** — one authoritative store.
- **Turn every hand-off into captured signal** — the Tier-1/2 signal above falls out of normal
  operation instead of being thrown away.

It also lets us *delete* the misfiring borrowed scaffolding (see audit), which is not merely redundant
but actively pointing at agents that don't exist in this runtime.

## First concrete steps (small, real, in leverage order)

1. **Strip the misfiring/dead OMC scaffolding** — the `[DELEGATION NOTICE]` regex (fires on every
   `2>/dev/null`), the `code-simplifier` Stop hook (auto-refactor vs. terse discipline), the RALPH
   persistence loop (fights aleph turn control), dead `clangd`/`typescript` LSPs, redundant
   agent-deck/herdr presence writers. Remove false-rigor at the source.
2. **Collapse the four memory stores toward funes** as the single source of truth.
3. **Native coordination plugin** (the lead direction above) — hand-offs + review via funes coworkers.
4. **Stand up the aleph affordance event log** (Tier 3) — smallest piece that unlocks the biggest gap;
   funes' forget-at-recall is already a usage-ranking engine that can consume it.
5. **Baseline characterization** from old convos (blocked once — see below; the data is at
   `~/.claude/projects/**/*.jsonl`, 188 files / 205M).
6. **Weekly reflection funes task** that grades the last week's work-units for stickiness + usage.

## Evidence appendix (investigations 2026-08-20)

### Config audit — the borrowed brains are misconfigured for this runtime
OMC was configured 2026-03/04 for bare-terminal Claude and **never re-tuned after the funes/aleph
buildout** (all August). Under aleph it has become a second, older orchestration brain:
- **`[DELEGATION NOTICE]` mis-fires on read-only commands** — `pre-tool-use.mjs:201-212`
  `FILE_MODIFY_PATTERNS` includes `/>\s*[^&]/`, which matches the `2>/dev/null` in nearly every shell
  command. Loudest hook, pure noise, trains the reader to ignore it.
- **It points at agents that don't exist here** — CLAUDE.md + the hooks recommend
  `Task(subagent_type="oh-my-claudecode:executor")`, but the OMC cast (executor/architect/planner/…)
  is **not registered** in the aleph/FleetView runtime (only `claude`, `Explore`, `general-purpose`,
  `Plan`, `superpowers:code-reviewer`, etc.). The advice targets nothing.
- **`code-simplifier` Stop hook** (`code-simplifier.mjs:73-84`) blocks each Stop to inject an
  auto-refactor pass — against the repo's terse/minimal commit discipline + human STACK review.
- **`persistent-mode` RALPH loop** (`persistent-mode.mjs:711-740`, `defaultExecutionMode:"ultrawork"`)
  Stop-blocks to force continuation — fights aleph's own turn/attention control.
- **Four memory systems**: funes (authoritative under aleph) · `.claude/projects/.../memory/` (31 files,
  duplicates funes, some entries describe funes internals) · OMC `.omc/notepad.md` (`<remember>`) ·
  episodic-memory (conversation recall). Plus duplicated "verify-before-done" (×3), delegation (×2),
  plan/execute (×2).
- **Triple-firing on shared events**: SessionStart + Stop each run three hooks; agent-deck and herdr
  both report agent-busy presence — redundant with each other and with aleph's own presence model.
- **Dead weight**: `clangd-lsp` + `typescript-lsp` plugins in an Elixir/Nix repo; `frontend-design` in a
  Raxol TUI; stray `~/.claude/*.bak` backups.
- **GAP confirmed — zero outcome/usage signal.** Every hook fires on intent-time events (PreToolUse,
  Stop, …); nothing observes whether a change landed, was used, or got reverted. Notable given funes'
  forget-at-recall is exactly an outcome/usage-ranking engine.
- Genuinely useful survivors: the **project** `.claude/settings.json` (sandbox + real Bash allowlist,
  well-tuned), `model: opus[1m]`, vim mode, episodic-memory for cross-conversation recall.
- Key files: `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/.omc-config.json`,
  `~/.claude/hooks/{pre-tool-use,code-simplifier,persistent-mode}.mjs`.

### Convo mining (baseline) — DONE (raw-transcript extractor over 188 files / 570 operator turns)
The counterfactual "how it actually goes" bar. This should govern what the value loop optimizes FOR.

- **Terseness is the defining fact.** Median operator message = 86 chars; 47% under 80. He steers on
  loose reins: short direction → let Claude drive → screenshot → terse verdict → "keep going."
- **Corrections are gentle and rarely about code.** The recurring kinds: mental-model/scope ("it's
  more meta than that"), taste ("too gimmicky", colors), and **anti-verbosity** ("take that fluff
  out"). Almost no anger, no "you keep doing X", no revert-in-rage.
- **Success = the live app, not the suite.** Praise is the biggest signal category and cheap
  ("sounds great", "looks great", screenshots). He accepts by clicking around, not by green tests.
- **Work is ~94% agent-harness R&D** (aleph/funes/tlön/nix) — design/UX iteration + infra + memory
  plumbing, debugging throughout. Plus OSS release ops (excessibility) and prod firefighting.
- **Takeovers are operational, not code-quality**: he keeps merge/publish/secrets/privileged steps,
  and runs other models (fable/glm/deepseek) in parallel windows, relaying state by hand.
- **Standing preferences** (the ~5 durable rules worth promoting): terse load-bearing comments only
  (no devlog prose) · zero warnings · clean tree / one main · bake knowledge into AGENTS.md/docs ·
  internalize recurring gotchas (e.g. git-status-outside-sandbox).
- **The real, repeated pain is CONTINUITY + operational overhead across many parallel short-lived
  sessions** — he is the human runbook, re-relaying state, re-explaining mental models, re-hitting
  gotchas. That is precisely where funes earns its keep: surface the standing rules + known gotchas
  *before* he restates them, carry design intent between sessions, and close the dogfooding
  self-service loop (self-cleanup/reset/restart) he keeps flagging.
- **It tips into ceremony** the moment it front-loads approval gates or verbose status on a guy whose
  median instruction is 86 chars. Anything that makes him type more, or read a devlog he said to
  delete, works against the grain. (Directly implicates over-long assistant messages — including this
  session's.)

### OMC cleanup applied 2026-08-20 (global, backed up)
- `pre-tool-use.mjs`: `checkBashCommand` now strips fd/stderr redirects (`2>/dev/null`, `2>&1`, `&>`)
  before the write-check — kills the `[DELEGATION NOTICE]` false-positive. Backup:
  `pre-tool-use.mjs.bak-before-fdredirect-fix`. (Aside: `.ex`/`.exs` were never in the source-ext
  list, so the notice only ever mis-fired on `.mjs`/`.sh`/etc.)
- `settings.json`: removed the two Stop hooks that fight aleph — `persistent-mode.mjs` (RALPH
  self-continuation loop) and `code-simplifier.mjs` (auto-refactor vs. terse discipline); kept
  `agent-deck`. Removed dead `clangd-lsp` plugin (no C/C++; kept `typescript-lsp` — manos is TS).
  Backup: `settings.json.bak-before-omc-cleanup`.
- Left for the operator's call (global blast radius / intentional tools / structural): the CLAUDE.md
  OMC instruction block (still points at unregistered `executor`/`architect` agents), the four-way
  memory consolidation toward funes, and agent-deck/herdr presence writers.
