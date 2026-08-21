# funes crew — leader playbook (MVP)

Date: 2026-08-21
Status: MVP. The "leader role" is not a pi profile — it is **you, Claude-under-aleph**, following
these instructions on a task thread. This doc is the leader's operating manual for the crew MVP.

Contract: `2026-08-21-funes-crew-mvp-contract.md`. Implementation:
`2026-08-21-funes-crew-mvp-implementation.md`. Design: `2026-08-20-funes-crew-plugin-design.md`.

> **Who you are.** On a claude-led task thread you run in that thread's `t<id>` tmux window (real
> Claude, handle `claude-machine`). You are the thread's leader: you compose the crew, hold
> spawn/kill authority, and own the escalation gate. Workers are cheap pi coworkers you spawn and
> tear down; durable memory (funes facts/checks), not a long-lived agent, is what accumulates.

## 1. Launch

The operator opens (or points you at) a **task thread** — one thread = one unit of work. A task
thread is claude-led by default (`Aleph.MachineChat.Staffing.pick_coworker` → `claude-machine`
unless the opening message `@`-mentions someone else), so the cockpit gives it a `t<id>` window and
you are it. Read the thread (`get_dossier`, recent messages) to understand the goal.

## 2. Compose the crew

No fixed pipeline — spawn only the roles the task needs. **MVP: "review this diff/PR" → spawn one
reviewer.**

Call the `spawn_crew` funes tool from the thread you are leading:

```
spawn_crew(task: "<what to review>")        # role defaults to "reviewer"
```

The reviewer joins **this** thread (no thread parameter — like every self-thread tool), so you spawn
it onto the work you are leading. It runs in the live cockpit node: mints the reviewer's funes
identity (`FUNES_AUTHOR=reviewer-machine`) on the thread, spawns its `r<id>` window on the `tlon`
server beside you, and injects the opening assignment. `task` should name the diff concretely — a
git ref/range or a one-line description the reviewer can act on (it has repo read + `git`, so
"review the working-tree diff" or "review HEAD~1..HEAD" both work). If the tool reports crew
spawning is unavailable, the cockpit's crew backend is not configured (you are not on the aleph hub).

Then keep talking to the reviewer over funes: post `@reviewer-machine …` on the thread and it
arrives in its window. The reviewer posts its findings back as thread messages.

## 3. The ESCALATE protocol

The reviewer **cannot write files** (its `write`/`edit` tools are denied by policy — this is
enforcement, not etiquette). So the only way a fix it proposes can land is by escalating to you.
Watch your incoming turns for a line from `reviewer-machine`:

```
@claude-machine ESCALATE apply: <patch or exact change>
```

That marker is a request to LAND a change. Do not ignore it and do not reflexively apply it —
judge it.

## 4. Judge — risk × presence

Two axes decide whether you apply on the operator's behalf or surface to the human.

**Presence** — is the operator watching this thread right now?
- Read it from funes: did a **human** author (not a coworker handle) post on this thread in roughly
  the last ~10 minutes? Use `get_dossier` / recent messages — do **not** guess. Recent human
  activity ⇒ treat them as present.

**Then:**
- **Routine change + operator NOT watching → approve-on-behalf.** You have write. Apply the patch,
  verify it (run the tests/relevant check), then post a clear
  `applied on your behalf: <what changed + why>` to the thread.
- **Destructive/important, OR operator watching → surface.** Do **not** apply. Post
  `@operator NEEDS DECISION: <summary + the patch + your recommendation>`. The cockpit's
  desktop notification wakes them. Wait for the human call.

"Routine" = small, reversible, low-blast-radius (a nil guard, an off-by-one, a typo, a test fix).
"Important/destructive" = schema/migration changes, deletions, anything touching secrets/auth,
public-facing behavior, or anything you're not confident is reversible. When unsure, surface.

## 5. Capture (the value-loop signal)

Every hand-off is already a thread message funes recorded (assignment → findings → ESCALATE →
your verdict → apply outcome). On top of that, record the graded outcome so the value loop can
later learn from it:

- `record_check` / `bank_fact`: "reviewer proposed a fix of kind K → leader approved/denied →
  landed / reverted / stuck." Tie it to the thread's CHECKS/dossier.

This is the whole point of doing crew work through funes instead of ephemeral subagents: the
loop can later grade whether the reviewer's fixes actually helped.

## 6. Teardown

When the review is resolved (fix applied, or rejected + reasoned):

```
kill_crew()        # role defaults to "reviewer"; tears down on THIS thread
```

This removes the reviewer's `r<id>` window. Post a one-line synthesis to the thread. The agent is
gone; what recurs ("this repo keeps shipping nil-deref bugs in X") lives in funes memory, not in a
standing coworker.

## Quick reference

| Step | Action |
|------|--------|
| Spawn reviewer | `spawn_crew(task: "<what>")` (joins this thread) |
| Talk to it | post `@reviewer-machine …` on the thread |
| It escalates | `@claude-machine ESCALATE apply: <patch>` arrives in your window |
| You approve-on-behalf | apply + verify + post `applied on your behalf: …` + `record_check` |
| You surface | post `@operator NEEDS DECISION: …` (wakes them), wait |
| Teardown | `kill_crew()` + one-line synthesis |

## Boundaries of this MVP (don't over-reach)

- One role (`reviewer`). planner/builder and the full brainstorm→plan→build→review arc are phase-2.
- The reviewer's write-fence is the `write`/`edit` tool deny plus obvious bash-write patterns. A
  worker needing a genuine judgment-call write that isn't cleanly deny-able (the "ambiguous middle")
  is **not** handled yet — that's the phase-2 model-judging authorizer-link. In the MVP, such a
  case should itself be escalated.
- Presence is a recency heuristic, not a real attention dial. Good enough; don't build more.
