# Funes must forget — recall as the seat of memory

**Status:** design, validated 2026-08-19 (brainstormed with Andrew). Centerpiece of the
"office standup" work seeded by the `munder-difflin` review ([[munder-difflin-stealables]]).

## The problem

funes is named for Borges' *Funes the Memorious* — the man cursed with perfect memory who
could not think *because* he could not forget. We built the curse: total recall, "return every
row, uncapped," append-only, nothing lost. Over a long-running office that man goes insane
(can't find the signal), and — because every session reloads its whole past — **bankrupt**
(context load is the dominant per-turn cost). Memory quality is *forgetting* quality.

## Thesis: forget at recall, not at storage

Storage stays append-only and total — funes keeps its real strengths: nothing is ever lost,
everything is auditable, no risky LLM-rewrite to verify. **The intelligence moves to
retrieval.** What reaches an agent's context is a small, ranked, **token-budgeted working
set**. Stale, unverified, superseded, low-signal facts fall out of *context*, not off *disk* —
recoverable by an explicit deeper search, never gone. Like human memory: you don't delete a
memory, it just stops surfacing unless it's salient or rehearsed.

Rejected alternative: forget-at-storage (munder's condense/delete model). Real data loss,
needs an LLM summarizer we don't have, throws away auditability. Not for us.

## The working set

The bounded slice of memory that reaches context, assembled fresh at two moments:
- **session start** — replaces today's fixed ~32 always-loaded constraints.
- **on-demand recall** — `search_facts` / `get_dossier` / brief during work.

Bounded by a **token budget, not a row count** — so cost per turn is bounded *by
construction*. This is the same lever the cost breaker watches: **memory load and spend are one
number.**

## Scoring: `relevance × strength`

**Relevance** — how well a candidate matches the current thread/query. Blend of:
- keyword FTS (have it today), and
- semantic cosine over local **ollama embeddings** (minilm / embeddinggemma — already wired,
  cf. [[ollama-pi-wiring]]). Embed-on-write + a vector column; brute-force cosine over our
  small N (hundreds–low-thousands of facts) is nothing.

**Strength** — `a decayed sum of signed, weighted touches`. A touch is an event funes already
records:

| touch | sign / weight |
|---|---|
| created | baseline |
| cited-and-used (agent acted on a recalled fact) | small + |
| recheck passed (`recheck_fact` → `check_passed`) | **big +** — "it keeps working" |
| recheck failed (`→ check_failed`) | **−** — active demotion, sinks fast |
| superseded / contradicted | hard − |

Empirical touches (a real `check_cmd` passing) outweigh restatements — strength scales with how
*sure* we are. A fact used repeatedly over months that keeps passing checks stays warm as raw
age grows; a one-off opinion fades; a fact whose last recheck *failed* drops out even if it was
strong yesterday. Memory that learns what's load-bearing.

**Discipline:** few weights, and *do not calibrate them by feel* — start with ~4–5 values and
tune from real usage. No precise curve up front (YAGNI).

## Verification half-life

Where "verify-don't-trust" actually belongs in funes — not condensation. A `checked` fact is
not checked *forever*: its check has an age, and a stale check decays the fact's certainty back
toward `opinion` until re-run. "We verified X" quietly loses authority unless re-confirmed.
`recheck_fact` is the rehearsal move for verification specifically. Certainty order
(`stated > checked > opinion`, `Funes.MCP.Brief.certainty/1`) becomes time-aware.

## Pinned floor

Operator-`stated` constraints never decay — the permanent core. Today's
`always_loaded_constraints/0` becomes the pinned floor of the working set; everything above it
is ranked-and-budgeted.

## Wiring

Existing threads / DB rows are **disposable** (Andrew, 2026-08-19) — design toward the ideal
schema and migrate freely; do not contort to preserve current data. Storage stays append-only as
a *principle* (auditability, no silent loss), but the shape is ours to reshape.

A **recall layer** (`Funes.Recall`) in front of the existing reads (`Funes.Dossier`,
`Funes.MCP.Brief`, `search_facts`). It scores candidates by `relevance × strength`, fills the
token budget from the top, returns the working set.
- **Strength** (`Funes.Recall.Strength` — *built, 12 tests*) — decayed sum of signed touches,
  from the events table; compute on-read first, materialize only if slow.
- **Certainty** (`Funes.Recall.Certainty` — *built*) — perishable `:checked`, feeds display and
  ranking.
- **Semantic** (`Funes.Recall.Embedding` — *built: cosine + ollama `embed/1` over `:httpc`,
  live-smoked*) — add a **first-class embedding vector column** on `fact`, embed-on-write in
  `bank_fact`, cosine at recall, blended with FTS into the relevance term.
- **Cited-and-used touch** — a **first-class** `cited` event kind + a light `reinforce` verb, so a
  fact an agent actually acted on earns a positive touch (in scope now — was only deferred to dodge
  a migration we're free to make).
- **Budget** is a config knob; it is also the breaker's memory-cost lever.

## Explicitly NOT doing

- No storage deletion / condensation. No LLM memory-rewrite.
- No verify-on-supersede gate — in a forget-at-recall world, supersede just demotes ranking; it
  never deletes, so there is nothing to guard (the earlier #2 "gate" solved a non-problem).
- `backup-before-nuke` on `clear_machine_threads` remains a cheap, orthogonal safety — a
  footnote, not part of this design.

## Open / deferred

- Weight + half-life calibration (from real usage, not by feel).
- On-read vs incremental strength materialization.
- How "cited-and-used" is detected (auto-infer from a recall citation vs an explicit `reinforce`).
- Whether the working set is assembled per-thread or office-wide (cross-thread shared recall —
  the "shared brain" axis; likely a later term once single-thread recall is proven).

## Build status (2026-08-19, branch `funes-forgetting-engine`)

**Engine complete — committed, funes suite green (261):**
- `Recall.Strength` — memory strength = decayed sum of signed touches (created/cited +,
  check_passed ++, check_failed −, superseded −−).
- `Recall.Certainty` — verification half-life (`:checked` earned + perishable).
- `Recall.Embedding` — cosine (pure) + ollama `embed/1` via `:httpc` (live-proven).
- `Recall.assemble/2` — pure working-set core (relevance × strength, pinned floor, token budget).
- `Recall.working_set_for_thread/2` — DB gatherer: real facts → strength-ranked, constraint-pinned,
  budgeted; relevance = **semantic (cosine) soft-OR keyword (FTS)** blend.
- `fact.embedding`/`embedding_model` columns (`VectorColumn`) + `store_embedding`/`embed_fact`;
  `reinforce_fact` (cited touch); `Search.matching_fact_ids/2`.

**Remaining = INTEGRATION / cutover (reserved for Andrew — touches live write + read paths):**
1. Call `embed_fact/1` after `bank_fact` (config-gated `embed_on_write`, default off) so facts get
   embedded automatically. A one-off backfill embeds existing facts.
2. Wire `working_set_for_thread` into the session-start brief / `get_dossier` behind a flag; flip it
   to make the working set the live memory.
3. `home:switch` + live MCP smoke; review before merge to main.

## Relationship to the other office-standup features

The **token budget is the seam** to the cost breaker (`Funes.Presence.Engine` backend fed by
the usage accumulator). Memory and cost governance are the same problem viewed twice: an office
that never forgets reloads an ever-growing past every turn → bankrupt. Forgetting *is* cost
control.
