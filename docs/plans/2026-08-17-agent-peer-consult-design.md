# Agent-to-agent consult — when pi wanted a second opinion from claude

Written 2026-08-17, opening thread 11 (Tlön). Trigger: a deepseek-v4-flash pi session, facing a
design call it was told to "escalate to claude", could not reach claude — no agent-invocable path
existed — so it fell back to typing `tmux send-keys` into claude's window. It worked, and that is
exactly the problem: the stack's coworkers have no *clean* way to talk to each other, so a model
MacGyver'd a terminal hack instead. This doc records the confirmed attribution bug and its fix
(shipped this session), then designs the missing capability.

Two independent defects surfaced, and they are not the same bug:

1. **Attribution — a commit signed by the wrong model.** The session metadata said `deepseek-v4-flash`
   but the commit trailer read `Co-Authored-By: GLM-5.2 (pi)`. *Confirmed mechanism:* pi (the harness)
   does **not** generate commit trailers at all — no `Co-Authored-By` literal exists in the binary.
   The model writes the trailer by following the repo's AGENTS.md rule, whose *example* hardcoded
   `GLM-5.2`; a weak model copies the example verbatim, and its own model name is never injected into
   the session. Fix shipped here (see §1): the brief now states the model's identity explicitly, and
   the AGENTS.md rule no longer offers a concrete name to copy.
2. **Consult — no agent-invocable way to ask a peer.** `/consult` delegates to a *transient model*
   (`minimax-m3`), not the *running claude session*; funes messaging is async (post to your own
   thread). Neither is "wake my coworker and hear back." Design in §2.

---

## 1 · Attribution: confirmed root cause and the fix (done)

**pi does not sign commits.** Grepping the packaged binary (v0.84.2) finds `GLM-5.2` and `Claude
Fable` (the model registry's display names) but **zero** occurrences of `Co-Authored`, `noreply`,
`(pi)`, or any trailer template. So the trailer is model-written, from the repo's guidance. The
guidance said:

> `Co-Authored-By: GLM-5.2 (pi) <noreply@ollama.com>` — e.g.

A flash model, told its identity nowhere else, copied the *example*. The session metadata knew it was
deepseek; the model didn't reliably read that. That's the "pi doesn't self-report its model" the brief
described — true in outcome, wrong about the layer: pi has no self-report to fix, but the repo never
told the model who it was.

The fix has two halves, both landed this session:

- **`modules/manos/pi/src/brief.ts`** — `renderBrief/3` now takes a `model` and, when present, emits a
  `You are <model> (pi).` line in the session's brief (the `before_agent_start` injection), fed from
  `process.env.PI_MODEL`. Every pi session now wakes already knowing which model it is.
- **`AGENTS.md` "commit as who you are"** — the rule now reads the model from the brief's `You are …
  (pi)` line / `$PI_MODEL`, and shows only a `<your model>` placeholder. No concrete name remains to
  copy by mistake.

The claude-code adapter (`brief-hook.sh`) renders through funes' Elixir brief, which is model-agnostic
by design (funes doesn't know which model connects), so no code change there — Claude self-reports
reliably, and the rewritten AGENTS.md rule already applies. Verified: `mise run manos:pi:check` green
(15 tests incl. a self-report pin).

## 2 · Consult: the design

### 2a — Why pi couldn't reach claude

- **The routing was a human affordance.** "Escalate design calls to claude via `Ctrl+Space o`" is an
  *aleph operator keybinding* — pi lives inside the Tlön pane and cannot press the cockpit's own keys.
  Never route an agent through operator-only UI; that is a routing-design bug (root `AGENTS.md` §Picking
  a model should carry this lesson).
- **`/consult` is a model, not a coworker.** `manos/consult` spawns a transient `pi -p` one-shot
  (`minimax-m3` default) — a fresh brain, no memory of the running claude session, no access to the
  thread's live state beyond what the transcript carries. Good for a second *opinion*; useless for
  *delegating to the person who's mid-task*.
- **funes is async, thread-bound, and address-by-connection.** An agent posts to its OWN thread
  (identity rides the token; thread params were deliberately removed). It cannot post to a peer's
  thread, and delivery is durable-not-live. The wake machinery exists (`Funes.Switchboard` + `Mentions`,
  `@mention` → poke the addressed recipient) but is **off by default and not presence-gated** — its own
  moduledoc says it should not auto-poke real panes until presence exists.

### 2b — Options

| Option | What it is | Verdict |
|---|---|---|
| **A · `consult_peer` funes tool** | New MCP tool: `consult_peer(peer, prompt)` → funes posts to the peer's *thread* with an `@mention`, and the switchboard (once presence-gated) wakes that peer's live session. Agent-invocable, reuses `Mentions` + `Switchboard`. | **Recommended.** Reuses existing machinery; a peer who is *offline* degrades honestly to an async thread note (no invented liveness). |
| **B · cross-session route** | A tool funes routes to a *live* session by presence, blocking for a reply. | Most "chat-like", but requires productionizing the off-by-default switchboard + a presence arbiter first — the larger build. Land after A. |
| **C · legitimize the tmux hack** | A manos tool that `tmux send-keys` a prompt into claude's window and reads back. | Rejects: it's the raw terminal hack, couples manos to aleph's tmux layout, and bypasses funes' single-writer/durability discipline. Good as a *last-resort* escape hatch, never the surface. |

### 2c — Discoverability (the operator's "point at the surface" fix)

Whatever lands, it must be *nameable from inside Tlön*. Concretely:

- The **brief** should name the consult surface once it exists — a `You can ask a coworker with
  consult_peer(peer, …)` line, and `/consult`/`/fresh` as the in-session second-opinion commands, so a
  model never again improvises a `tmux send-keys`.
- The **coordinate-via-funes skill** should point at `consult_peer` and `/consult` as the escalation
  path, replacing the operator-keybinding routing that failed.

### 2d — Deferred, and why

Building A touches funes' boundary (`lib/funes.ex` exports), which is deliberate by design — "the
surface creeps only on purpose, reviewed in this file's history." It also needs the presence-gated
switchboard to actually wake a live peer, which the switchboard's own moduledoc flags as not-yet.
So the sequence is: (1) ship attribution (done), (2) get sign-off on A's surface widening, (3) land
presence-gating, (4) build `consult_peer` + name it in the brief/skill. This doc is step 2's artifact.
