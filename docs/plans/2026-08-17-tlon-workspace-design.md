# Tlön as a self-contained workspace — and the three ways agents reach other agents

> **Status 2026-08-17 — mechanisms 2 and 3 shipped.** The three-agent-mechanisms framing below
> is the load-bearing part and stands. Mechanism 3 (`consult_peer`, the funes-mediated coworker
> consult) is done — `61a552b`, `ac9f86c` — and mechanism 1 is the normal Tlön move. Mechanism 2
> (a model-callable `consult` TOOL returning its answer mid-turn-safe, promoted from the human
> `/consult`/`/fresh` commands) shipped in `6d657b8`: `manos/consult` now `registerTool`s a
> `consult` tool that runs the same `pi -p` delegate but returns-as-result instead of
> `sendUserMessage`, dissolving the refuse-mid-turn limit §2d described. The commands stay the
> human doors; the tool is the model's. The remaining open item is Work-sequence #3 (generalize
> Tlön spawning), a mechanism-1 nicety, not a cross-agent mechanism.

Written 2026-08-17 (branch `dogfood-kitty-keys`). Settles what Tlön *is* after live use, and
untangles three mechanisms that had been collapsed into one ("consult"). The trigger: the Tlön
center had accumulated seed cruft, six duplicate machine threads, and a pile of zombie sessions,
and the pi/claude "two windows" raised the question of what Tlön is actually *for*.

## Tlön is a self-contained meta/dogfooding workspace

Tlön is the space for working **on the machine/stack itself** — not a project, not a coworker's
thread. Concretely:

- **A self-contained tmux workspace.** The Tlön center is a real tmux session; pi is window 0, the
  planner/orchestrator. From there pi (or the operator) opens the windows the work needs — a claude
  to implement, plain terminals to run things. It is pi's workshop, not a single fixed pane.
- **pi is a funes citizen on ONE stable machine thread.** `machine_exports` find-or-creates by
  `Channel.machine_thread/0` (latest open `scope: "machine"` thread) and joins it; aleph never closes
  it on shutdown, so it is reused across restarts. One Tlön thread, not one-per-boot. Zombie sessions
  self-reap via `start_session`'s supersede on that single (thread, agent) pair.
- **Self-contained — it does not leak.** Tlön's tmux windows are local to the Tlön center; they are
  not Sessions-space coworker terminals and not Comms threads. The workshop stays in the workshop.
  (The six duplicate threads + zombie sessions that polluted the roster were the find-or-create gap,
  now closed; the historical cruft was wiped.)
- **aleph owns the chrome.** The embedded tmux's own status bar is turned off; aleph renders the
  workspace's windows as a clean `pi · claude · …` tab strip in its Tlön header, active highlighted —
  the cockpit's look, not raw tmux.

## The three ways an agent reaches another agent — NOT one thing

These were blurred under "consult". They are distinct, all wanted, and each is the right tool for a
different job:

### 1 · Delegate *work* — `-p` / spawn a window
A worker (fresh, or briefed) *does a discrete task* and exits. `claude -p "build X"` headless, or an
interactive claude window when you want to steer, or a plain terminal. **The window is the
delegation.** This is pi's primary move in Tlön: plan in pi, spawn a claude to build. No live-session
bridge, no presence — you spawn a worker to do the thing.

### 2 · Consult a *model* — `/consult [model]` (v1 / manos/consult), made agent-invocable
One model taps a **different or smarter model** for an answer — deepseek-flash asking glm because glm
is smarter, or pi asking chatgpt/claude. Transient (a fresh instance of that model), with **varying
context**: none (`/fresh`), or the recent transcript (`/consult`). It is about reaching *another
intelligence*, not a specific colleague or their state.

Under the hood this IS `-p`: `/consult` and `/fresh` spawn a transient `pi -p --no-session --model
<id>` (manos/consult), `/consult` handing it the session transcript, `/fresh` a clean prompt.

**The gap, precisely.** `/consult`/`/fresh` are `registerCommand` and **refuse mid-turn** — but not
because pi forbids a model calling them (v1 pi had a model-callable `/consult`). They refuse because
they hand the answer back via `sendUserMessage`, which *triggers a new turn* and would stack turns if
the agent is mid-flight. A command and a tool are the **same capability with two surfaces**, so the
fix is to add the *model* surface: a `registerTool` (`consult`) that runs the same `pi -p …` delegate
and **returns the answer as the tool result** instead of `sendUserMessage`. Returning-as-result is
mid-turn-safe by construction (no new turn), which dissolves the refuse-mid-turn limit. Keep
`/consult`/`/fresh` as the human commands; add the tool for the model, with a `model` and a
context-level (`none`/`transcript`) argument. Same engine, two doors — the two-doors pattern manos
already uses for funes.

### 3 · Consult a *coworker* — `consult_peer` (really consult_*coworker*)
Reach a **specific live coworker** and get an answer back into your own thread — with *their*
accumulated context, on their real thread. Agent-to-agent, funes-mediated (the built-and-verified
bidirectional mirror). This is a *colleague* consult: "the claude that's already working on thread N,
what do you think?"

**Its scope is OUTSIDE Tlön.** The coworker analogy breaks down inside Tlön — there, pi doesn't
consult a peer, it *spawns the tools it needs* (mechanism 1). So `consult_peer` is for the broader
multi-coworker world, and its deferred machinery (presence-gating to wake live peers, auto-close
lifecycle) is only worth building when a live-coworker-consult need actually shows up — do not
over-invest ahead of that.

### How they compose in Tlön
pi plans → **spawns windows** to build (1), **consults a model** for a smarter opinion mid-plan (2);
**consult_coworker** (3) is the outside-Tlön case pi rarely needs in the workshop.

## Work sequence

1. **Cleanup + find-or-create — DONE.** Cruft wiped (`aleph:reset:db`); find-or-create verified
   (one stable open Tlön thread, reused across restarts; zombies self-reap).
2. **aleph renders window tabs + tmux `status off` — DONE.** Clean tab strip in the Tlön header
   (`2efd711`), the workspace made a plain tmux session (`383b735`).
3. **Generalize Tlön spawning.** `^o` claude (interactive) + a `claude -p` discrete-build path + a
   plain-terminal-window verb — all inside Tlön's tmux.
4. **Make model-consult agent-invocable — DONE** (`6d657b8`, mechanism 2). `manos/consult` now
   `registerTool`s a `consult` tool the model calls mid-turn: the same `pi -p` delegate as
   `/consult`/`/fresh`, but returning the answer as the tool result (mid-turn-safe) with a
   `context: none|transcript` argument. The slash commands stay the human doors.
