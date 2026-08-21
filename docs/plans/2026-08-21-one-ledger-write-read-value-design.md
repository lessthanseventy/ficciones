# One Ledger: making claude, pi, funes, and aleph reach toward the same thing

**Date:** 2026-08-21
**Status:** design (validated in brainstorm; not yet implemented)

## Thesis

Memory ≡ coordination ≡ goal. They are not three layers — they are one substance
(the funes ledger) seen from three angles:

- **Memory is coordination at rest.** Agents here coordinate *by* reading and writing
  the shared thread. An `@mention` is a write that wakes someone; an `ESCALATE` is a
  write that hands work up; a `bank_fact` is a write the next agent reads. Coordination
  is memory in motion.
- **Memory is the goal made inspectable.** You cannot know whether work moved the needle
  except through a record of what happened. The value signal is a *read over accumulated
  memory*. The goal is the gradient the memory is shaped by.

The identity is the north star. It is **not yet true in the implementation** — today the
ledger is keyed on *correctness* (`check_cmd`/exit code), not *value* (usage/outcome),
and writes can silently land in a private brain. The work is to close the seam so
remembering-well, coordinating-well, and pursuing-value-well become the **same operation
on the same ledger**.

## The one loop

```
        ┌─────────────────────────────────────────┐
        ▼                                          │
   WRITE (reflexive, carries intent)               │
        │                                          │
        ▼                                          │
   READ  (pushed + ranked)  ═══ is ═══ WAKE/route  │
        │                                          │
        ▼                                          │
   VALUE (mined from the ledger's own traffic) ────┘
   → weights READ's ranking + WRITE's survival
```

An agent writes what it learned/did → the next read surfaces it → the value signal grades
whether it mattered → that grading shapes the next write (what survives, what surfaces).
Coordination is this cycle among multiple agents.

## Where it is severed (four cuts) and how to close them

### Cut 1 — Write: the ledger is the reflexive default

**Goal:** durable machine-knowledge lands in funes automatically, for every agent, so no
private second brain accumulates. Convention is insufficient — proven 2026-08-21 when
claude-machine banked the crew-MVP knowledge to its private Claude file-memory instead of
funes. This cut is a **reflex + a contract**, not a rule.

**The write contract (shared by all four agents):**
- how-something-works / a load-bearing gotcha / a decision → `bank_fact`
- a shipped, judgeable outcome → `record_done`
- a measured check → `record_check`
- an open blocker / question → `raise_issue` / `raise_question`
- Private store (claude file-memory, pi context) is demoted to **session-continuity only**
  ("where we are", operator preferences) — never machine knowledge.

**The reflex (per harness, same job, one policy in aleph):**
- **pi** — extend the existing note-nudge (every 8 turns): route the candidate to
  `bank_fact` instead of a private note.
- **claude-machine** — no equivalent exists today (the hole). Add an aleph turn-end / Stop
  hook that scans the turn for a durable claim and prompts "bank this?" → `bank_fact`.
  Same shape as pi's nudge, different harness.
- aleph hosts both reflexes as **one policy** so the trigger logic lives in one place.

**Forward-compat:** every write carries **intent** (*what it was for*) from day one, even
before value telemetry exists. `bank_fact`/`record_done` grow a purpose/expected-outcome
field — the hook Cut 3 grades against. Write value-shaped now; fill the gradient later.

**Success test:** run a task, write nothing to a private brain by hand; afterward the
machine-knowledge is all in funes, discoverable by another agent.

### Cut 2 — Read: recall is pushed, ranked, and it *is* coordination

**Goal:** the fact an agent needs is already in front of it at turn start — no
`search_facts` by hand. Pull becomes as automatic as push.

**Mechanism (build on what exists):** the forget-at-recall engine already does relevance
ranking + budget-capped forgetting; `get_dossier` already assembles a thread brief. The
gap is that this is *fetched*, not *pushed*.
- **Every agent gets a turn-start recall preamble** — top-K ledger slice, budget-capped by
  forget-at-recall — injected before it acts. For pi coworkers this rides the dossier into
  the turn preamble; for **claude-machine**, aleph injects the funes dossier into the same
  context slot the private `MEMORY.md` auto-loads into today — now sourced from the shared
  ledger. This retires the private-brain default: the auto-injected context *becomes* funes.

**The unification (payoff of memory ≡ coordination):** surfacing the right fact to the
right agent and waking the right agent with a mention are the **same act**. The
recall-surfacer and the mention/wake router (Aleph.Mention Bus) become **one
ranked-delivery mechanism** sharing one relevance×value ranker. A recall is a self-wake;
a mention is a recall someone else aimed at you.

**Ranking now vs later:** until value telemetry lands (Cut 3), rank by a proxy — recency,
verification status, recall-frequency. The ranker has a value slot from day one.

**Success test:** an agent begins a turn and the fact it needs is already present; a
mention and a recall visibly flow through the same delivery path.

### Cut 3 — Value: the gradient, mostly mined from the ledger itself

**Goal:** every write accrues *whether it mattered*, and that score feeds back into the
Cut-2 ranker and the Cut-1 forgetting budget. "Are we jerking off?" becomes computable.

**The unlock — the three value tiers are not equally hard:**
- **Outcome** (have it): `record_check` exit codes, `record_done`. Did it verify/ship?
- **Interaction** (free, unbuilt): mine it from the ledger's own events — how often a fact
  is recalled, whether a recall *preceded* a `record_done` or a passing `record_check`
  (recall→action), replies/mentions it drew, whether its `check_cmd` still passes on
  re-verification. A fact's value ≈ its downstream pull; funes computes it with no new
  plumbing.
- **Usage** (the real gap): did the product actually get used, did the operator keep the
  change. External telemetry — deferred, but the intent field reserves the slot.

**Feed it back (this closes the loop):** the interaction score becomes the **value weight**
in the shared recall/wake ranker (Cut 2) and the **survival weight** in forget-at-recall
(Cut 1). Banked-but-never-recalled, spawned-but-nothing-shipped → low value → forgotten
and de-ranked. Recalled-and-acted-on → surfaces first, survives. No human labeling — the
ledger grades itself from its own traffic.

**Success test:** two facts — one repeatedly recalled-then-acted-on, one orphaned; the
ranker surfaces the first and forgets the second, unlabeled.

### Cut 4 — Coordinate: falls out of the first three

Not a separate build — the proof the three were one thing:
- A `spawn_crew` / `@mention` / `ESCALATE` is a **write** (Cut 1).
- The wake/mention router **is** the recall-surfacer (Cut 2).
- A coordination act is graded by the **same interaction-value** (Cut 3): a spawn that led
  to recall→action→`record_done` scores; one that went nowhere is visible busywork.

Close Write→Read→Value and Coordinate closes itself.

## Who each actor becomes

- **funes** — the one ledger: storage + ranker + forgetting + value computation. The brain.
- **aleph** — the nervous system: hosts the write-reflex hooks, injects the recall
  preamble, runs the unified recall/wake router, surfaces the value readout (a Tlön
  "are-we-jerking-off" panel).
- **pi coworkers** — hands that write/read/act through the ledger; note-nudge → `bank_fact`.
- **claude-machine** — same contract, no exceptions: private memory demoted to
  session-continuity, context injected from funes, writes reflexive.

They reach toward the same thing because there is no longer four things — four hands, one
value-ranked ledger.

## Roadmap

Order: **Write → Read → Value**; Coordinate falls out. Each stage is shippable and
dogfoodable in the aleph cockpit (Tlön).

1. **Write** — write contract + per-harness reflex (extend pi note-nudge → `bank_fact`;
   add claude-machine turn-end "bank this?" hook in aleph) + intent field on
   `bank_fact`/`record_done`.
2. **Read** — turn-start recall preamble for every agent (funes dossier pushed into
   context, budget-capped); collapse recall-surfacer and mention/wake router into one
   ranked-delivery mechanism.
3. **Value** — compute interaction-value from the ledger's event stream; wire it as the
   weight in the Cut-2 ranker and Cut-1 forgetting; add the Tlön value readout. Tier-3
   usage telemetry deferred (slot reserved by the intent field).
