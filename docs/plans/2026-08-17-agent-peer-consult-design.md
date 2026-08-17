# Agent-to-agent consult — when pi wanted a second opinion from claude

Written 2026-08-17, opening thread 11 (Tlön). Trigger: a deepseek-v4-flash pi session, facing a
design call it was told to "escalate to claude", could not reach a *running* claude session through
any first-class path, so it fell back to typing `tmux send-keys` into claude's window. It worked, and that is
exactly the problem: the stack's coworkers have no *clean* way to consult each other, so a model
MacGyver'd a terminal hack instead. This doc records the confirmed attribution bug and its fix
(shipped this session), then corrects the record on what messaging surface already exists and what
narrow gap remains.

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

### 2a — What messaging surface already exists (corrected, verified 2026-08-17)

The original draft said "no agent-invocable path existed". That was wrong — I checked what a pi
session actually has loaded, and the surface is richer than the draft credited. The real gap is
narrow and precise.

**What a pi session on this stack has today:**
- **`/consult [model] <prompt>` and `/fresh [model] <prompt>`** (the `manos/consult` extension, loaded).
  These delegate to a *transient one-shot model* (`minimax-m3` default) — a fresh brain for a second
  opinion, with `/consult` carrying the recent session transcript. **But** they are human-invoked
  slash commands: the extension refuses while the agent is mid-turn, and the model can't type slash
  commands — the operator runs them. So they are *not* an agent-invocable peer consult.
- **funes MCP tools** (`post_message`, `bank_fact`, `raise_issue`, `record_done`, `get_dossier`).
  `post_message` writes to the session's OWN thread (identity rides the token; thread params were
  deliberately removed from the tools), so it cannot target a peer's thread.
- **`scripts/funes-cli.sh`** from the shell (`roster`, `dossier <id>`, `post <id> <text>`, `spawn`).
  This CAN read any thread's brief and post to any thread — but `post` speaks as the **operator**, not
  as the agent, and the parity tools were flaky at the time of writing (a node EADDRINUSE on :7456
  broke `roster`/`dossier`).

**So the gap is exactly one thing, not "messaging" as a whole:** there is no first-class,
 agent-invocable tool that reaches a *running peer session* and gets a direct answer. Everything else
 exists and is findable; that one live-peer hop is missing. The routing bug below is
 independent: even with `/consult` in hand, telling an agent to "escalate to claude via `Ctrl+Space o`"
 was unactionable because that is operator-only UI — never route an agent through operator-only
 keybindings, a routing-design bug on its own.

### 2b — The design: `consult_peer` as the third deliberate cross-thread verb

`OpenThread` and `CloseThread` are the only two tools that act off the connection's own thread —
`CloseThread`'s moduledoc calls itself "the sanctioned exception to 'no tool takes a thread
parameter'." `consult_peer` is the third such verb, and it earns the exception for the same reason
the other two do: the act is inherently about *another* thread, and there is no thread to misdirect
because the caller never names one.

**Tool shape**

```
consult_peer(peer: agent_name, prompt: string) → {consult_id, peer_thread_id}
```

**How it resolves without fighting the token/session model**

- The call authenticates as the caller via the connection token → frame binds (caller_thread,
  caller_agent, caller_session). `consult_peer` reads ONLY that — no peer thread id comes from the
  call, so misdirection is unrepresentable, the same rule PostMessage's no-thread-param enforces.
- `peer` is an **agent name** (`Staff.agent_by_name/1`), never a thread id. funes resolves the peer's
  current thread from its live session (`Staff.live_session` / `threads_for`). The caller asks for a
  *coworker*, not a thread — how a human would address them.
- funes (the single writer) creates the consult as a `Channel.post` on the peer's thread, authored by
  the **caller's real agent identity** (`caller_agent`). No adapter writes cross-thread directly; the
  write is mediated by funes exactly like `post_message` is, just to a resolved target thread. The
  adapter stays a client of the channel.

**Two delivery modes, one contract**

- **Durable (works today):** the consult is a normal message on the peer's thread; the peer sees it on
  its next dossier refresh (or the switchboard's `@mention` wake if that lands). No liveness is
  invented — an offline peer finds the consult waiting, which is honest.
- **Live wake (the optimization, presence-gated):** when the switchboard is presence-gated, the
  delivered consult pokes the peer's live session (the `Funes.Switchboard` + `Funes.Mentions`
  machinery exists for exactly this). The tool's *contract* is durable delivery; the wake is a latency
  improvement on top, never assumed.

**Boundary cost**

One new export in `lib/funes.ex` (a `Consult` context, or a `Channel`-adjacent function) plus a new
`Funes.MCP.Tool.ConsultPeer` component and the `consult_peer` directTool. That is the whole surface —
and it is the reviewed, deliberate widening this file's history is for.

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

### 2e — Review checks (for the second set of eyes)

Before anyone builds this, verify each against the codebase — a `consult_peer` that *looks* right but
fights the token/session model is exactly what this pass is for:

- **Author / misdirection.** The consult must be authored by the CALLER's real agent identity, and the
  caller must never pass a thread id — only a peer *agent name*. If `consult_peer` lets a caller post
  to an arbitrary thread, or as the operator/peer, it breaks both the misdirection rule and the
  single-writer discipline. Reject.
- **Single-writer.** The cross-thread write must go through `Funes.Channel.post` (or a new `Consult`
  context that itself calls the channel) — never a direct schema write from the tool. The new export
  must live inside the `lib/funes.ex` boundary, not widen it accidentally.
- **Presence honesty.** The tool must not claim the peer read, will answer, or is live. Delivery is
  durable; a wake is gated on presence-gating landing. Any "answered"/"read" claim is invented.
- **Offline degradation.** A consult to an agent with no live session must land durably and be
  readable later — never a dropped message or a false failure.
- **Unknown/duplicate peer.** `peer` is `Staff.agent_by_name`. On an unknown or ambiguous name, refuse
  (like `CloseThread`'s missing-id refusal) rather than guess.

Known open questions for the review: should the consult appear in the peer's brief as a distinct kind
(so it reads as "asked you something", not ambient chatter), and should a consult ever auto-close when
answered? Both are surface/UX choices that don't change the token/session mechanics above.
