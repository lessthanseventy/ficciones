# Tlön-shaped flows — the ask-matt map on our substrate

Andrew, 2026-09-08: "that, but tlön shaped." The mattpocock-skills router describes one main flow
(idea → ship), two on-ramps, and a vocabulary layer, all on top of a git repo + an issue tracker +
a fresh agent session per ticket. Tlön already owns every one of those substrates. This maps each
element to its Tlön object, marks what exists, and names the gaps — most of which the UX slices
(`2026-09-08-cockpit-ux-principles-design.md`) already schedule.

## The substrate swap

| ask-matt assumes | Tlön has | status |
|---|---|---|
| a repo + working directory | workspace (repos + roster + policies) | slice 5 tables |
| an issue tracker (GitHub / `.scratch/`) | tickets — separate objects, tied to threads or not, with blocks/relates/duplicates/parent links | slice 4 |
| a fresh agent session per ticket, `/clear` between | a coworker per ticket: cold → fresh, dossier-seeded, never `/resume` | lifecycle design 2026-09-01; `Staffing.spawn_onto/2` on ticket-promote EXISTS |
| `CONTEXT.md` (glossary) + ADRs | funes facts (`bank_fact`), decisions as a fact kind; the dossier is the read model | facts exist; a `decision` kind is slice 3 (message/fact kinds) |
| the "smart zone" (~150k) | coworker rotation keyed to cache TTL / context budget + dossier catch-up | episodes + rotation memory; OPEN |
| `/setup-matt-pocock-skills` | workspace policies (permissions, drivers, labels) | slice 5 policy table |

## The main flow, on Tlön

1. **`/grill-with-docs`** → a thread with the operator and the lead. The interview is the
   conversation (principle: the conversation is the record); what it learns lands as facts, not a
   file. `/grill-me` (stateless) is the same thread without banking.
2. **prototype detour** → a worktree thread (`Worktree`, slice 4A of the cockpit plan, exists) on
   `prototype/<name>`; **`/handoff`** in both directions is the dossier: `get_dossier` out, a
   dossier-seeded coworker in. No markdown file crosses hands.
3. **`/to-spec`** → a spec message kind on the thread (slice 3) or a `docs/plans` doc committed
   from it; **`/to-tickets`** → tickets with blocking edges as `ticket_link` rows (slice 4), so
   "any ticket whose blockers are done can be grabbed" is a query, not a hand-worked list.
4. **`/implement` per ticket** → one coworker per ticket, `/tdd` inside it, the mise gate as its
   check, then **`/code-review`** = two review COWORKERS (standards, spec) — not subagents; that
   was already the lead move in the value-loop plan. Commit trailers credit the model that wrote it.
5. **`/clear` between tickets** → the coworker is torn down; the next one is fresh. The thread
   stays as the record.

## On-ramps

- **`/triage`** → the TRIAGE pane (exists, in the drawer after slice 1) + keyword triage from the
  per-thread-agents design. Only for what arrived raw; tickets born from `/to-tickets` skip it.
- **`/diagnosing-bugs`** → a bug ticket whose first artefact is the tight loop (one mise command
  red on this bug), then the regression test; the post-mortem is a fact.
- **`/wayfinder`** → a channel (slice 1b) of decision tickets; a decision closes its ticket with a
  `decision` fact; `/to-spec` collapses the channel. Never resolve more than one per coworker.

## Codebase health + vocabulary

- **`/improve-codebase-architecture`** → the `maintain` workline (workline SDLC design: maintain,
  ledger, eval). Its output is a candidate ticket, which re-enters at step 1.
- **`/domain-modeling`** → the glossary is facts; overloaded words are resolved by `forget_fact` +
  `bank_fact`. **`/codebase-design`** stays a skill (vocabulary, no state).

## Phase boundaries, on Tlön

| option | Tlön move |
|---|---|
| continue | same thread, same coworker |
| `/clear` | new thread |
| `/handoff` | the dossier (`get_dossier` → a seeded coworker); a Brief for a human |
| subagent | a leaf coworker on the thread (per-thread agents design) |
| `/compact` | rotation: cold → fresh coworker seeded from the dossier catch-up |

## Standalone

`/research` → a research coworker on a cheap driver (ollama level 1–2) that leaves a note with
citations (Notes-reimagined backlog). `/to-questionnaire` → a question message kind addressed to a
human (slice 3: questions roll up as messages). `/wizard` → operator-only verbs; the cockpit is the
wizard. `/wait-what` → a reply in the thread. `/resolving-merge-conflicts`, `/prototype`,
`/teach`, `/writing-for-agents` stay skills as-is.

## Gaps this adds to the slices (nothing new outside them)

- slice 3: a `decision` fact/message kind; `spec` and `question` kinds (already listed).
- slice 4: `ticket_link` blocking edges + "grabbable" query; ticket-promote spawns a coworker
  with the ticket as its brief (extend `spawn_onto/2`).
- slice 5: policies carry the review-coworker drivers and triage labels; that IS the
  `/setup-matt-pocock-skills` answer for this repo ("some other workflow you describe" = the
  funes MCP ticket verbs).
- open: rotation keyed to a context budget (the smart zone) — not scheduled; belongs with
  one-brain B (sessions → server).

The router itself becomes a Tlön skill once the tickets exist: `ask-matt` answers "which flow", the
cockpit's `New` menu answers "which object".
