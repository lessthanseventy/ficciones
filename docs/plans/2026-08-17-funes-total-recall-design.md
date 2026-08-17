# funes: total recall — memory parity with pi-memory/hermes, done the funes way

*2026-08-17. Design doc. Triggered by "should pi get pi-memory/pi-hermes-memory too?" The answer:
no second memory system — funes IS pi's memory, and it's ahead on what matters. But the sweep
surfaced real gaps (full-text search, automatic capture) worth closing natively. Funes is named for
Borges' "Funes el memorioso," who forgot nothing; this is the module earning the name.*

## The frame

funes already beats pi-memory/hermes on the parts that matter: a **structured, provenance-ranked**
store (`stated > checked > opinion`) in SQLite, with the curated brief **auto-injected** at session
start (`Resource.Dossier`/`Constraints`/`Habits` via `before_agent_start`). Its DB + rank-and-cut
reads **obviate** the char-limit/auto-consolidation machinery those extensions spend most of their
code on. So this is not catch-up — it's closing two narrow, real gaps and adding automation.

### Capability map (funes vs pi-memory / pi-hermes)

| Capability | them | funes today | verdict |
|---|---|---|---|
| Durable structured store | flat, char-capped MD | dossier: provenance + certainty + closed vocab | funes wins |
| Auto-inject memory at session start | policy/legacy block | Resource.Dossier/Constraints/Habits | already automatic |
| Consolidation / char-limit mgmt | LLM merge/prune on overflow | queryable DB + rank-and-cut reads | obviated |
| User profile | USER.md | stated constraints + HABITS | have |
| Procedural skills | SKILL.md | manos skills | have (manos) |
| **FTS keyword search** (facts + past sessions) | SQLite FTS5 | none | **GAP → build** |
| **Auto-capture at boundaries** (compaction/shutdown) | handoff/flush | none | **GAP → build** |
| **Correction detection** → save | auto | none | **GAP → build** |
| Secret scanning on write | blocks keys | none | **small add** |
| Semantic/vector search | optional (qmd) | none | deferred (FTS covers ~90%) |
| Delete + recover | forget/restore | supersession (immutable ledger) | funes' model — keep |

## The principle: automation feeds the low-authority lanes; humans promote

The one rule that lets funes automate hard without breaking its discipline:

> **Auto-capture always lands as `derived` facts, events, or `pending` habit-proposals — never
> auto-`stated`, never auto-approved.** A robot fills the bottom lanes; the human promotes from them.

This is *why* hermes' auto-consolidation felt wrong (it promotes agent conclusions to authority) and
this doesn't (it keeps them subordinate). Every automation below obeys it: a detected correction
becomes a **pending habit** you approve, not a silent constraint; a session-end extraction banks
**derived** facts (ranked opinion/checked), never stated ones.

## The slices

### A. FTS search foundation (funes) — effort M
SQLite **FTS5** virtual tables shadowing `message` (and `fact`), kept in sync by triggers. Two MCP
tools: `search_history` (past conversations, returns `thread:message` refs + snippets) and
`search_facts` (the corpus past the brief's cap). This is the foundation everything else searches.
- First step: **verify FTS5 is compiled into exqlite's SQLite** (a `CREATE VIRTUAL TABLE … USING
  fts5` probe). If absent, fall back to `LIKE`/`trigram` — decide before building.
- Reads are ranked (bm25) + capped-and-counted, like every funes read.

### B. Secret scanning on the write path (funes) — effort S
A regex/entropy scan in `bank_fact` (and `post_message`?) that refuses obvious secrets (API keys,
tokens, SSH keys, `AKIA…`, high-entropy blobs) before they land. Cheap, high safety — and it guards
the *automated* capture below from banking a leaked key it read in a buffer.

### C. Boundary auto-capture (manos/pi) — effort M
On **compaction** and **session shutdown**, the pi extension runs one extraction pass (cheap model):
"what durable facts / decisions / questions surfaced this session?" → banks them **derived** (with
`check_cmd` when reproducible) + records a `work_landed`/handoff **event** summarizing the session.
One LLM call per boundary — low noise, high value. Unit-test the prompt-building + response-parsing;
the live extraction is the eye-test.

### D. Active capture: background review + correction detection (manos/pi) — effort M–L
- **Background review** every N turns / M tool-calls: extract lessons/failures → derived facts.
- **Correction detection**: "don't do that" / "use X instead" / "actually, …" patterns →
  `propose_habit` (PENDING, for approval — the provenance-safe path). The pattern match is pure +
  unit-tested; the classify-borderline-cases step (optional) is an LLM call.

### E. Noise control (config + aleph) — effort S
A `~/.pi/agent/funes-recall.json` (owned like `provider-failover.json`): toggles + intervals for
each automation (`boundaryCapture`, `backgroundReview.everyTurns`, `correctionDetection`,
`autoInjectSearch`), a master `enabled`, and a verbosity level for what capture announces. Plus an
**aleph keybind** to mute/unmute auto-capture live (a status glyph shows the state). This is the
"knob to control the noise" — automation you can turn down without a redeploy.

## Explicitly skipped (low-utility-and-hard, or against the model)

- **Auto-consolidation / char limits** — funes is a queryable DB with rank-and-cut reads; there's no
  document to overflow. Structurally unnecessary.
- **Semantic / vector search (embeddings)** — needs embedding infra for marginal gain over FTS5;
  deferred until FTS proves insufficient.
- **Delete + recover** — funes is an append-only ledger; supersession (explicit, provenance-checked)
  is the deliberate answer to "this is wrong now." A delete+restore path would fight that.
- **Per-turn search-injection before every turn** — re-searching + re-injecting each turn churns the
  prompt prefix and fights KV-cache stability (see `2026-08-16-context-reuse-cribs.md`). Kept as a
  config-gated, default-OFF option in slice E, not a default.

## Sequence

A (search foundation) → B (secret-scan, guards C/D) → C (boundary capture) → D (active capture) →
E (noise control, lands alongside C/D as they generate output worth muting). A+B are funes/Elixir —
fully TDD'd. C+D are manos/pi — pure pieces unit-tested, live LLM extraction is the eye-test. E is
config + an aleph keybind (keymap is test-covered).
