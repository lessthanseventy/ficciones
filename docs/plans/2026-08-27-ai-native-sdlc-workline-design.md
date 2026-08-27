# AI-native SDLC → worklines: design

2026-08-27. Sources mined: Anthropic's AI-native SDLC playbook (six stages, artifact chain, hooks-vs-skills, continuous evals) and OpenExecutive (eval-driven config development, cache-disciplined context injection, post-response memory pass, claim-safe scheduling). This doc bakes both into the funes/aleph coworker + workflow model. It is the concrete shape of the "native funes-coordination plugin" named as the lead move in `2026-08-20-value-feedback-loop-design.md`.

## Core loop

A unit of work is a **workline**: one funes thread bound to one world, paired with a git folder in that world's tree (`work/<slug>/`). The folder accumulates the artifact chain; git history of the folder is the audit trail. Nothing about the chain lives only in funes.

The thread carries the **stage state machine**:

```
intent → spec → plan → build → verify → review → merged
                                                    ↑
                            maintain ── machine-born intent
```

Stage state is a thread attribute in funes, not parsed from files. Every transition goes through one new funes tool, **`advance_stage`**, which enforces the invariant: *no advance without the stage's owed artifact committed*. The tool verifies the artifact exists in git (recorded as a CHECK via `record_check`) before flipping state.

Transitions have two flavors:

- **Auto-advance** (human-born intent→spec, plan→build, build→verify, verify→review): funes flips the stage and wakes the responsible actor over the existing Aleph.Mention/Bus route with a stage brief.
- **Gated** (spec→plan, review→merged, machine-born intent→spec): funes parks the thread in `awaiting:andrew`, surfaces it in the cockpit attention row, and nothing moves until approval.

Rationale for gate placement: judgment at intent and integration, autonomy in between (playbook-classic). Machine-born intents are additionally gated because the Maintain loop must never start work unsupervised.

## Artifacts

Each stage owes exactly one committed artifact:

| Stage | Artifact | Author | Notes |
|---|---|---|---|
| intent | `intent.md` | originator | Andrew's words near-verbatim + one-line restatement; machine-born cites breach evidence, lands gated |
| spec | `spec.md` | bound worker | requirements + design in one session (playbook sd-s2); worker interviews Andrew in-thread; standards come from world knobs + stage playbooks, not re-asking. First human gate. |
| plan | `plan.md` | bound worker | bite-sized tasks, writing-plans style; auto-advances |
| build | the branch | bound worker | commits on a workline branch; no separate file |
| verify | CHECKS | verifier | evidence entries, not prose |
| review | `review.md` | review coworker | findings vs spec/bugs/security + verdict; merge gate reads this. Never written by the builder. |
| maintain | `incident.md` | diagnostic coworker | only born from Maintain; links breach → blamed workline |

The dossier **indexes** artifacts, never contains them: a FACT per committed artifact (path + rev), CHECKS for verify evidence, TODOS mirroring `plan.md` tasks, QUESTIONS carrying gate requests. Catch-up stays cheap because artifacts re-read from git.

**Cache discipline** (OpenExecutive): briefs put stable content (persona, world knobs, stage playbook) in the cacheable prefix; artifact content and dossier catch-up inject into the turn, never the prefix.

## Actors

- **Bound worker** (per-thread-agents model, any harness) carries intent→spec→plan→build. On stage entry it gets a stage brief; rotation mid-workline is safe because a fresh agent rebuilds from artifacts + dossier (never `/resume`), with a defined read-list per stage.
- **Verifier** — ephemeral coworker, NOT a subagent of the builder (a builder-spawned verifier is self-certification by proxy: the builder authors its context). On verify entry, funes spawns it onto the thread with a fixed brief; it drives a deterministic **`workline:verify` script** (module gates + flake:check — the machine gate, per the verify-before-done rule), records evidence as CHECKS, advances or bounces, and is torn down. Cheapest driver available; the script does the work, the model interprets failures.
- **Review coworker** — the funes-native reviewer (see `2026-08-21-funes-native-review-coworkers-design.md`). Writes `review.md`, fenced to that file plus reads. Cannot advance the stage; only Andrew's merge approval does.

**Model routing per stage** is a world knob, overridable per workline: spec + review on the strong bucket (Claude — lean on it), build per-item, verify + mechanical plan expansion on cheap drivers (haiku/sonnet, low ollama levels).

## Governance: hooks vs skills

Rule of thumb: *if breaking it should be impossible, it's a permission-system entry; if breaking it should be rare, it's prompt material.*

**Hooks** (deterministic — pi-permission-system + pi-sandbox + manos, flake-seeded per profile):
- builder write-fence on test files during build/verify (failing tests are read-only to the builder — prove the fix, don't mask it)
- reviewer fence: write `review.md` only
- `advance_stage` refusing transitions without the owed artifact
- branch protection: nothing merges without the human gate
- (later) the parked bash-judge as an authorizer-link

**Skills** (advisory — flake-owned, version-controlled, picked up on respawn): stage playbooks, world knobs, coworker personas. When a coworker makes the same mistake twice, the correction goes into the stage playbook or world knobs (the CLAUDE.md discipline, funes/flake-native).

## Evals on the steering config

The convergent steal from both sources. Under test: the coordination layer, not app code — triage routing, stage briefs, personas, `advance_stage` gating, fence compliance, catch-up fidelity. Today a prompt edit can silently lobotomize a coworker; this closes that.

- **Corpus**: in-repo scenarios (~15 to start), four families: routing, stage discipline, fence compliance, catch-up fidelity. Fixture input + judged dimensions.
- **Judge**: LLM-as-judge on a cheap driver (sonnet/haiku — not Opus; the $100 bucket is for real work), 1–5 per dimension with rationale. Deterministic scenarios (fences, gating) are plain asserts, no judge.
- **Gate**: `mix funes.eval` standalone; flake:check runs it when steering files change (briefs, personas, triage config, permission seeds). Threshold ≥3.5 average, hard-fail on any deterministic assert.

**Memory pass** (OpenExecutive): after a worker turn completes, a haiku-tier background pass extracts decisions/initiatives and `bank_fact`s them. Event-shaped, off the latency path, replaces turn-count nudges, feeds the same dossiers the briefs read.

## Maintain back-edge + value ledger

**Maintain**: deterministic monitors, no human in the invocation path. A scheduled check (the recurring-tasks/Oban space; `UPDATE … RETURNING` claim pattern prevents double-fire) evaluates version-controlled **control bands** per world: gates green on main, funes service up, eval scores above floor, orphan leaves, stale `awaiting:andrew` gates. On breach: spawn a cheap diagnostic coworker → it writes a machine-born `intent.md` citing evidence (+ `incident.md` on the blamed workline) → lands gated.

**Ledger**: every `advance_stage` call is a timestamped event, so the playbook's indicators are free — this is the outcome-tier of the value-feedback-loop, obtained as a side effect.
- Leading: intent→spec time, spec→plan time, first-pass verify rate, gate-wait time.
- Lagging: intent survival rate, review findings → merged fixes, post-merge drift from `plan.md`, machine-born intent accept-vs-reject rate (is Maintain producing value or noise?).
- Surface: `mix funes.ledger` read-model over stage events; aleph panel later.

## Excluded (YAGNI + anti-steals)

No unified-voice front (coworkers stay visible — aleph's attention design is the point). No multi-channel integrations. No ChromaDB (funes recall is the retrieval layer). No per-stage archetype roster. No separate CI service — flake:check is the CI.

## Slices

0. **Eval harness** — `mix funes.eval`, judge plumbing, first ~15 scenarios against today's steering config, flake:check wiring. First: protects everything later, depends on nothing.
1. **Stage machine** — thread stage attribute, `advance_stage` + artifact enforcement, gate states, `work/<slug>/` convention. Pure funes, testable agent-free.
2. **Briefs + wakes** — brief assembly (prefix/inject split), per-stage catch-up lists, auto-advance wakes over Mention/Bus, `awaiting:andrew` in the cockpit attention row.
3. **Fences + reviewer** — permission-system seeds for both fences, reviewer brief, merge gate reads `review.md`; fence eval scenarios ride along.
4. **Verifier** — `workline:verify` script, ephemeral spawn/teardown on verify entry, CHECKS recording.
5. **Memory pass** — post-response haiku extraction → `bank_fact`. Independent after slice 0.
6. **Maintain + ledger** — control bands per world, claim-safe scheduled monitor, machine-born intents, `mix funes.ledger`.
