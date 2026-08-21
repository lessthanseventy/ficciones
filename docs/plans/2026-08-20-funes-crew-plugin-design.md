# The funes crew plugin — native coordination for Claude-under-aleph

Date: 2026-08-20
Status: early design / will evolve. Born from the 2026-08-20 "are we just jerking off?" thread
(operator + `claude-machine`) and its value-loop doc (`2026-08-20-value-feedback-loop-design.md`).
Captures the lead direction: replace the three borrowed coordination brains (OMC, superpowers, and
Claude's own `Task()` fan-out) with a funes-native crew, so every hand-off is a durable thread
message the value loop can learn from instead of an ephemeral subagent that vanishes.

## The shape

- **A thread is a unit of work** ("task"), launched from aleph's chat space.
- **A leader** runs the thread — the agent the operator talks to. It **composes the crew**: given a
  goal + wherever the operator is starting, it decides which roles this task needs and drives
  progression. No fixed pipeline — a PR review spawns just a reviewer; a greenfield "I barely know
  what I'm doing" runs the full brainstorm→plan→build→review arc.
- **Role-coworkers** are **spawned per thread** from a role profile (planner / builder / reviewer /
  …), like `tertius` today, and torn down when done. Isolation is clean; accumulation ("what bugs
  recur here") lives in **funes memory**, not in a long-lived agent.
- The superpowers lifecycle is expressed as **which role is active on the thread**, as hand-offs
  between coworkers — and those hand-offs are thread messages funes already captures. That capture is
  the value-loop signal, for free.

## The warden (decided)

**One coordination brain: the Claude leader, via the plugin.** It wrangles the crew and holds spawn/
kill authority. It is Claude because the warden's whole job is judgment — which roles, when a role is
done, and (critically) the **escalation gate**: it's the thing that lets a background pi coworker run
loose safely.

The operator's real pain, in his words: *"I never found a good way to let pi do stuff in the
background without being permission-jumpy."* pi unattended either stalls on a prompt nobody answers or
yolo's into something dumb. The fix is not a model choice, it's routing permission escalations
**through the leader**:

- A pi coworker hits an ambiguous/risky call.
- Instead of prompting the human (jumpy) or yolo-ing (reckless), it **escalates to the leader**.
- The Claude leader judges: routine → approve on the operator's behalf, keep moving; genuinely
  important/destructive → *that's* when it surfaces to the human.

That is "pi's flexibility, Claude's when-to-interrupt judgment." It's the `pi-bash-judge` idea with
the judge being the thread's leader. (See `[[pi-bash-judge]]`, `[[pi-permission-model]]`.)

## Model routing — a dial, not a switch

Same Claude warden always; **presence changes only how freely it escalates**, not the warden's
identity:

- Operator in the thread → the leader asks more freely (they're right there).
- Nobody watching → the leader self-approves routine and wakes the human only for the important.

pi does the work (attended or not — flexible, cheap, funes-native); Claude leads and owns the gate.
Precedent already exists: `tertius` is a pi leader on the autonomous root thread — this is "tertius,
but Claude in the seat, and the seat is a permission gate." The deny-floor (`@tlon_permissions`) stays
the un-negotiable backstop under all of it.

## MVP / entry point

Start where the operator said he'd start: **"review a PR."** Smallest real slice — launch a thread,
leader spawns one reviewer coworker, review lands as thread messages, leader synthesizes + surfaces.
Proves the spawn → role → hand-off → capture loop end-to-end before adding planner/builder and the
full arc.

## Open (evolve it)

- What a "role profile" is concretely (prompt + tool cut + model) and where the role prompts live.
- The escalation protocol wire format — how a coworker asks the leader, how the leader answers, how it
  wakes the human (ties to the aleph `Aleph.Mention` bus + attention model).
- How the leader spawns/kills coworkers (extends the existing `n`/`s` cockpit spawn + arbiter).
- Whether the plugin is a Claude Code plugin, a funes/aleph capability, or both halves talking.
- How this reads/writes the value-loop signal (hand-off outcomes → funes CHECKS/dossier).
