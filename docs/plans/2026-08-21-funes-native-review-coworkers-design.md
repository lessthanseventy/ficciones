# Funes-Native Review Coworkers — Design Note

> Status: **design capture** (not yet a task plan). The forcing function for the long-recorded
> "write a native funes-coordination plugin — hand off to review COWORKERS, not superpowers
> subagents" lead move (see the `value-feedback-loop` memory). Sibling to the worlds/orbis reshape:
> Slice 1's per-task reviews are this substrate's first real customer.

## The observation that motivates it

Slice 0 was executed via superpowers `subagent-driven-development`: a fresh `general-purpose`
subagent per task, a `superpowers:code-reviewer` subagent after each. **The review gates earned
their keep** — they caught two real bugs a happy-path pass would have shipped:

- the Leaves-attach **TOCTOU half-attach** (two tmux snapshots; window vanishing between them →
  focus committed into a never-re-pointed center, no deferral flash), and
- the Orbis survey **rollup hammering funes every frame**, bypassing the 2 s probe throttle the
  module's own discipline mandates.

That is the "are we measuring value, not just correctness?" signal actually firing. So the *review
discipline* is worth keeping. What is **not** worth keeping is the *executor*.

## What's wrong with the superpowers executor (why move it)

The anonymous Task subagents are a stale second brain for *process*, the same shape OMC was for
memory (and OMC was ripped for exactly this reason):

- **No persona / no model-routing.** They run at the session model; your `subagent-model-routing`
  rule (pin fan-out reviewers to haiku/sonnet, reserve the session bucket) can't be applied.
- **No permission policy / no sandbox.** Unlike a funes coworker (`Aleph.Profile.permissions`,
  pi-sandbox allowlist), a Task subagent has no per-role gating.
- **No attribution.** Their commits don't carry the actual-model co-author trailer (the
  `commit-attribution-by-actual-model` rule); they were told to hand-set a Sonnet trailer, which is
  a guess, not ground truth.
- **Findings evaporate.** A reviewer subagent's output lives only in the leader's context. Nothing
  is banked, posted, or auditable. A funes reviewer coworker would post findings to the machine
  thread as messages / `raise_issue`, verifiable and re-readable.
- **External dependency.** superpowers is a marketplace plugin; the disciplines it holds should be
  sovereign funes data, not rented.

## The move: extract, then remove (NOT remove-then-scramble)

1. **Extract the load-bearing disciplines into funes-native form** — before touching superpowers:
   - the code-reviewer protocol (adversarial diff review, the Critical/Important/Minor rubric, the
     "verify against the real code, don't trust the report" stance) → a `reviewer` coworker
     archetype's system prompt (a **nix capability** / profile template, like `tertius`), plus a
     banked review-protocol fact or `propose_habit`.
   - the plan structure (writing-plans: bite-sized TDD tasks, exact paths, DoD) and the TDD /
     verification gates → banked facts / habits the leader and coworkers follow.
2. **Route reviews through the reviewer coworker on the machine thread.** The leader (tertius /
   claude-machine) hands each task's diff (BASE..HEAD SHAs) to a `reviewer` coworker via
   `spawn_crew` / a standing window; findings come back as machine-thread messages or issues,
   model-routed to sonnet/haiku, correctly attributed.
3. **Prove parity, then drop the dependency.** Only once the coworker review catches what
   superpowers caught this slice (re-run it against the Slice 0 diffs as a regression check) do we
   remove the superpowers reliance.

## Open questions (settle when this becomes a plan)

- **Reviewer coworker vs. leader-with-review-habit.** Is "reviewer" a distinct persisted coworker
  (its own window/socket, like hronir/uqbar), or a role the leader assumes per task? Distinct
  coworker gives isolation + model-routing; a role is lighter. Lean distinct.
- **Crew MVP fit.** `spawn_crew`/`kill_crew` exist (funes facts 32/33) with the inject-readiness
  gotcha. Does a per-task ephemeral reviewer crew fit that, or do we want a standing reviewer window
  in the Tlön world roster? (Ties into Slice 1's per-world roster.)
- **Findings vocabulary.** Do review findings map onto existing funes primitives (`raise_issue`,
  `raise_question`, `record_check`) or need a new `review`/`finding` shape? Prefer reuse.
- **Gate enforcement.** Is the review advisory (leader decides) or a hard gate (a failing review
  blocks the task commit / the branch merge)? Slice 0 treated it as fix-Important-before-next-task.

## Non-goals

Not rebuilding superpowers' whole skill catalog in funes — only the *coordination + review + plan +
TDD* disciplines that this workflow leans on. The rest (frontend-design, dataviz, etc.) stay as
skills; they're not coordination substrate.
