# Piece H — the three experiments (2026-09-18)

Master plan row H (`2026-09-17-ficciones-master-plan.md`), from the field survey's adopt #10
and #12: evals and audits, not builds. Each section says what was measured, on what, and what
it decides. Where the corpus is too small to decide, it says so; the eval shape is left in place
so the question can be re-run when there are threads.

**The corpus, as of this run.** The live store (Postgres `tlon`, cut over from SQLite 2026-09-18,
row-for-row) holds 8 threads, 13 messages, 13 facts (10 stated constraints, 3 stated decisions;
none forgotten, none embedded — ollama's embedder was never reachable from the store), 3 events
(2 checks), 9 sessions, 1 workspace. That is the whole of Tlön's own memory of itself. It is
enough to audit the machinery against; it is not enough to measure a ranking policy on.

---

## 1 · Query-driven brief vs the fixed budget (adopt #10)

**Question.** Sourcegraph's "5K of targeted retrieval beats a 100K summary" and CompactionRL
both say a brief should be *retrieval-first*. Tlön's brief already seeds recall with a query
(the thread title plus the operator's latest words — `Server.Board.brief/1` → `recall_query/1`
→ `Recall.thread_learnings/2`), then cuts the ranked set to a fixed token budget
(`Recall.@default_budget`, 4000). So the live question is narrower than the survey's framing:
**does the query change what reaches context, and by how much, versus uniform relevance?**

**Instrument.** For every thread: LEARNINGS with `query: nil` (relevance uniform, strength alone
orders) and LEARNINGS with the brief's own query; compare the shown sets. Deterministic — no
model call — so it can sit in `server:eval`'s deterministic tier as a regression: "the query
reorders at least one thread's working set", once the corpus has any thread where it can.

**Result** (run 2026-09-18 against the live store, after the release migrated it):

| threads | threads with facts of their own | LEARNINGS shown, no query | LEARNINGS shown, brief's query | differs |
|---|---|---|---|---|
| 8 | 0 | `[]` on every thread | `[]` on every thread | never |

All 13 facts are workspace-global seed constraints and decisions (`thread_id` nil — the wipe-proof
brand from `priv/seed/repo_knowledge.exs`); they reach the brief as the pinned always-loaded set,
not through the thread's ranked LEARNINGS. Not one thread has banked a fact of its own. The
query therefore has nothing to reorder and the budget nothing to cut.

**What it decides.** Nothing yet, and the reason is sharper than "too small": the corpus has no
*thread-scoped* memory at all, because the memory pass ran only as an opt-in GenServer that
depended on a live claude CLI, and every coworker turn to date happened on the standing thread.
E/2 makes the pass a job on every idle; the experiment becomes decidable once threads carry more
facts than 4000 tokens hold. The instrument is ready (the comparison is a 20-line script over
`Recall.thread_learnings/2` with and without `query:`), and the honest regression to add to
`server:eval`'s deterministic tier *then* is: "on the fixture thread with N facts, the query
changes the shown set".

---

## 2 · Forget-at-recall vs mem0's ADD / UPDATE / DELETE / NOOP (adopt #12a)

**mem0's procedure.** Extraction produces candidate memories; each is compared against the
existing store and the model returns one verdict: ADD (new), UPDATE (refines an existing memory
— the old text is rewritten), DELETE (contradicts an existing memory — it is removed), NOOP
(already known). Retrieval is hybrid (semantic + BM25 + entity graph) with temporal reasoning.
Forgetting is at *storage*: UPDATE and DELETE mutate the record.

**Tlön's procedure, read from the code.**

| mem0 verdict | Tlön today | Where |
|---|---|---|
| ADD | `Dossier.bank_fact/1` — every extraction is an insert; the extractor is told the existing facts and asked to skip what they cover (`Memory.Extractor.Claude` contract) | `memory/extractor.ex`, `memory/turn_pass.ex` |
| UPDATE | no rewrite ever; `supersedes` links a new fact to the one it replaces, and the old one gets a hard negative touch (`Strength` `"superseded" => -3.0`) so it falls out of context | `fact.ex` (`supersedes`), `recall/strength.ex` |
| DELETE | `Dossier.forget_fact/1` tombstones (`forgotten_at`); every recall surface excludes tombstones; the row stays for audit. Operator-only verb (`forget_fact` on the operator surface) | `fact.ex`, `dossier.ex:45`, `search.ex` |
| NOOP | the extractor's own judgement ("skip anything the EXISTING FACTS already cover") — no server-side dedupe | `memory/extractor.ex` |

**Gaps, in order of cost.**

1. **NOOP is not enforced.** Nothing stops a second extraction from banking a near-duplicate of
   an existing fact; the only guard is the prompt. mem0 makes the verdict explicit and checks it.
   Cheapest fix that keeps forget-at-storage out: before `bank_fact`, run the candidate through
   the same keyword relevance the recall layer uses (`Recall` keyword bm25 over `text_tsv`)
   against the thread's facts; a candidate whose top hit scores above a threshold is a NOOP
   (dropped) or — if the candidate is longer and contains the hit's claim — a supersede. This is a
   server-side verdict with no model call. *Not built*: it needs a threshold, and a threshold
   needs data (§1's problem again).
2. **UPDATE is a link, never a merge.** Tlön's stance (design 2026-08-19: forget at recall, not
   at storage) is deliberate — no LLM rewrite of the record. The cost is that a refined fact and
   its predecessor both exist, and only strength decay hides the old one. That is the design's
   own tradeoff and the audit confirms it holds: nothing in the code rewrites a fact's text.
3. **DELETE is operator-only.** An agent cannot forget a fact; it can supersede it. mem0 lets the
   model delete on contradiction. Tlön's choice is the safer one for a one-person system; the
   audit finds no case where an agent-driven delete was missed *and* needed, because supersede
   plus the -3.0 touch achieves the same recall effect within a day of the half-life.
4. **Temporal reasoning is decay only.** mem0 reasons about *when* a memory was true. Tlön has
   `created_at`, the touch timeline and the half-life; nothing says "true between X and Y". Not a
   gap for constraints and decisions (which are current or superseded); would matter for
   `learned` facts about a changing world. Defer until a real case appears.
5. **Retrieval is keyword + (nominally) cosine.** The corpus has zero embeddings — the embedder
   endpoint has never been reachable from the store, so relevance has been keyword-only in
   practice. The code degrades honestly (`@query_embed_timeout_ms`, `@relevance_floor`), but the
   audit's most concrete finding is operational, not design: **either point `config :server,
   :embedding` at a live ollama and backfill (`Recall.coverage/1` reports it), or stop carrying
   the cosine path.**

**Decision.** Keep forget-at-recall. Two follow-ups, neither urgent: the server-side NOOP verdict
(gap 1) once there is data to set its threshold, and the embedding backfill (gap 5) as a task, not
a design change.

---

## 3 · CHECKS up the evidence hierarchy (adopt #12b)

**The hierarchy** (Verification Horizon): deterministic tests → evaluator scores → historical
reliability, each mapped to reject / revise / escalate / merge.

**Tlön today.** A CHECK is an `event` row of kind `check_passed` / `check_failed` with
`detail = %{cmd, exit, tail}` (`Dossier.record_check/1`); a fact with a `check_cmd` can be
re-verified (`recheck_fact/2`, correlated `fact:<id>`); the brief renders the recent checks
(`Board.brief/1` → `recent_checks_for_thread/1`); strength weights a pass at +2.0 and a fail at
-2.0 (`Recall.Strength`); the workline's stop hook asks the artifact gate, not the checks
(`Workline.owed_status/1`); playbooks count `check_passed` events when promoting a solved thread
(`playbooks.ex:77`).

So Tlön sits squarely on tier 1 (deterministic, exit-code-keyed) with tier-3 *ingredients*
already recorded (every pass/fail is a row with a timestamp and a correlation key) but not
*derived*: nothing computes a fact's or a command's pass rate, and nothing maps a check's outcome
to a verdict beyond "shown red or green".

**Gap list.**

1. **Historical reliability is one query away.** Pass rate per `correlation` (or per `cmd`)
   over the event table is a read model, not a schema change: `count(check_passed) /
   count(check_*)` per key, with the last outcome and its age. Render it beside each CHECK line
   in the brief ("3/4, last failed 2d ago") and beside a checked fact's certainty
   (`Brief.certainty/1` says `checked`; it could say `checked 4/4`). Cheap; deterministic; the
   most useful single step up the hierarchy for a coworker reading the brief.
2. **Evaluator scores have no row.** A judged verdict (the eval harness's `Server.Eval.Judge`
   already produces 1–5 scores for steering scenarios) has nowhere to land on a thread. A new
   event kind (`check_scored`, `detail = %{score, judge, rubric}`) would fit the existing table
   without a migration beyond the kind CHECK constraint; strength would need a weight for it.
   Not built: no producer exists yet outside the eval suite.
3. **Verdict mapping is absent.** reject / revise / escalate / merge is the workline's business
   (the gate at each stage). Today the gate asks "is the artifact committed?", not "did the
   checks pass?". The smallest honest step: `Workline.owed_status/1` also reports the stage's
   last check outcome, and the stop hook's refusal text names a red check. Defer until #1 exists,
   so there is a reliability number to name.

**Decision.** Build gap 1 when a brief next needs it; it is an afternoon and has no design risk.
Gaps 2 and 3 wait for a producer of scores.

---

## What this leaves open

- §1's measurement needs a corpus with threads that outgrow the budget. The memory pass is now
  a job on every turn's end (E/2); the corpus will grow with use, not with effort.
- The embedding backfill (§2 gap 5) is an operational task: point the embedder at a live ollama
  and let `embed_on_write` do the rest; `Recall.coverage/1` is the gauge.
