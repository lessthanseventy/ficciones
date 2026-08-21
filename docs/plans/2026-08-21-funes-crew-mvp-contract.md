# funes crew plugin — MVP contract

Date: 2026-08-21
Status: firmed (brainstorm w/ operator + `claude-machine`). Implements the MVP from
`2026-08-20-funes-crew-plugin-design.md`; wires the value-loop signal from
`2026-08-20-value-feedback-loop-design.md`. This doc is the build contract, not the vision.

## What the MVP proves

The full loop, end-to-end, with the escalation gate **firing** (not deferred):

> Launch a thread → the leader spawns one reviewer coworker from a role → the reviewer reviews a
> diff and **proposes a fix it is not allowed to apply** → it ESCALATEs the write to the leader →
> the leader judges (risk × operator presence) and either approves-on-behalf or surfaces to the
> operator → the change lands → every hand-off is a thread message funes captured.

## Decisions locked

1. **Roles are seats, not identities.** "Leader" and "reviewer" are roles. A thread has one leader
   seat and N worker seats; each seat is filled by spawning a coworker from a role. A seat's driver
   is the role's default model, overridable per-launch via the existing per-coworker model knob
   (SETTINGS panel → `Aleph.Config.coworker_model`).
2. **Worker roles are pi profiles; the leader role is the plugin.** Worker personas live in
   `Aleph.Profiles` (compiled, like `@tertius_role`) and materialise to a pi config dir. The leader
   is real Claude-under-aleph following the crew-plugin instructions — NOT a materialised pi profile.
   ("Claude leader" = the leader role's default driver is Claude, because the gate wants judgment;
   drive it with glm and the wiring still holds, the judgment just gets dumber.)
3. **Reviewer default driver = glm-5.2** (cheap, funes-native worker); overridable.
4. **Same task thread, windowed coworker.** One thread = the unit of work. The reviewer spawns into
   a `t<id>` window on that thread, posts as messages, and is torn down when the leader is done.
   Accumulation ("what bugs recur") lives in funes memory, not a long-lived agent.
5. **Gate = the reviewer's write-deny permission policy + the ESCALATE mention protocol.** Enforced
   by the pi-permission-system deny-floor (unbypassable, like `tertius`'s), handed off over the
   mention bus (captured for free). No new authorizer-link, no blocking poll inside bubblewrap.
6. **The model-judging authorizer-link is phase-2**, for the *ambiguous middle* (a worker needing a
   genuine judgment-call bash/write that isn't cleanly deny-able). MVP's crux action (write a fix)
   splits cleanly deny-for-reviewer / allow-for-leader, so it doesn't need it yet.

## The three contract pieces

### A. Role-profile shape

A worker role = an `Aleph.Profile` entry, same struct as `tertius`. The `reviewer` role:

- `name: "reviewer"`
- `system_prompt`: the reviewer persona — review the diff, be terse/high-signal, and **never write
  files**. When a fix is warranted, post the patch and `@<leader> ESCALATE apply: <diff>`; wait for
  the leader's verdict; do not retry a denied write.
- `model`: `glm-5.2` default (overridable).
- `mcp`: the machine-citizen funes surface (`post_message`, `bank_fact`, `record_check`,
  `get_dossier`, `raise_issue`) — read + post. No file-write MCP.
- `sandbox`: `@tlon_sandbox` (repo readable; the write fence is the *permission* policy, below).
- `permissions`: a reviewer variant of `@tlon_permissions` — **Edit/Write tools → `deny`; the
  obvious bash-write patterns (`>` redirect, `sed -i`, `tee`, `dd`) → `deny`; reads/greps/git-read →
  `allow`; `yoloMode: true`** so the allowed reads never stall on an ask. The catastrophic deny-floor
  is preserved unchanged.

The leader "role prompt" is the crew-plugin skill Claude-under-aleph runs (compose crew, spawn/kill,
hold the gate) — it lives in the plugin, not in `Aleph.Profiles`.

### B. Spawn / teardown lifecycle

- **Spawn**: the leader spawns a coworker from the `reviewer` profile onto the task thread's `t<id>`
  window. Extends the existing `s` verb / `Aleph.Arbiter.spawn` / `Sessions.spawn_harness`, now
  parameterized by **role/profile** (today `s` spawns a single default coworker). Wires `FUNES_*`
  identity via tmux `-e`: `FUNES_AUTHOR=reviewer-machine`, `FUNES_THREAD=<task thread>`.
- **Mention registration**: `reviewer-machine` must resolve to the task thread's `t<id>` window in
  the mention router. The staffed-thread `opts[:staffed_window]` redirect already targets `t<id>`
  windows; the reviewer handle is registered at spawn and dropped at teardown.
- **Teardown**: when the leader is done (fix applied or rejected + synthesis posted), it kills the
  reviewer's window and unregisters the handle. Clean isolation; memory carries what matters.

### C. Escalation gate

- **Structural floor**: the reviewer literally cannot write (permission deny). Its only path to
  landing a change is to post the patch and escalate — enforcement, not persona etiquette.
- **Hand-off**: reviewer posts `@<leader> ESCALATE apply: <patch>` (a parseable marker in the body).
- **Leader judgment — risk × presence**:
  - *Presence read*: is the operator focused on / recently active in the task thread? (aleph knows
    focus via the cockpit space/thread + attention model.)
  - routine + operator not watching → **approve-on-behalf**: the leader applies (it has write, or
    spawns a builder seat) and posts "applied on your behalf: <what/why>".
  - destructive/important **or** operator watching → **surface**: wake the operator via the
    attention bus and wait for the human call.
- **Capture / value loop**: each {escalation → verdict → apply outcome} is a thread message; the
  leader also writes a `record_check` / `bank_fact` so the loop can later grade "reviewer proposed
  fix of kind K → leader approved/denied → stuck or reverted?" (ties to CHECKS/dossier).

## Explicitly out of scope (phase 2+)

- The model-judging authorizer-link for the ambiguous middle (decision 6).
- planner / builder roles and the full brainstorm→plan→build→review arc.
- A sophisticated presence dial (MVP: focus flag + recent operator activity is enough).
- The scheduled value-loop grading pass (MVP just *emits* the signal).

## Open (resolve during planning)

- Exact spawn seam: does `s` grow a role argument, or a new `spawn_role/2`? (Read `Sessions` +
  cockpit `s`/`n` handlers first.)
- How the leader reads operator presence for a given thread (existing aleph state vs a small addition).
- Where the `ESCALATE`/verdict markers are parsed — leader-side persona instruction (MVP) vs a
  structured funes verb (later).
