# Agent-to-agent consult — when pi wanted a second opinion from claude

> **Superseded 2026-08-17 — the build this review prescribed has shipped.** The step sequence it
> set (3: land presence-gating, 4: build `consult_peer` + the answer mirror) is done in `9df5c2b`
> (the switchboard), `03d326e` + `79ec9be` (a live `Aleph.Arbiter` over the embedded terminals and
> engine-credit presence), `61a552b` (`Funes.Consult.consult_peer/3` + the `consult_peer` tool), and
> `ac9f86c` (a consult ask rendered distinctly in the peer's brief). Every review check in §2e holds
> against the implementation — verified 2026-08-17. Keep this doc for the reasoning (especially the
> mirror's echo guard and the tie-break rule); build nothing from its "to do" framing.

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

`consult_id` correlates the pair — the ask the caller sent and the answer the peer gives. (The first
draft returned it without a backing schema; the return-path design below is what makes it real.)

**Hole 1 (review) — how the peer's target thread is actually resolved**

The first draft said funes "resolves the peer's current thread from its live session". That is wrong:
an agent maps to MANY threads (`threads_for/1` returns a list — its moduledoc says "an agent maps to
many threads"), and `live_session/2` takes a thread id as input — it is the token→identity resolver,
not a lookup-by-agent. There is no `current_thread_for_agent/1`. So `consult_peer("claude", …)` must
resolve over the peer's staffed threads with a defined rule, not a hop:

1. `peer` → `Staff.agent_by_name/1` (refuse unknown / duplicate name). This yields `claude.id`.
2. `threads_for(claude)` → every thread claude is staffed on.
3. For each, claude's live session via **`live_session(thread.id, claude.id)`** — NOT
   `session_for_thread/1`, which filters only by thread, not agent. A stray cross-agent session on a
   thread staffed to claude must not misroute the target; filtering by the `claude.id` we already hold
   is the cheap guard. Filter to live.
4. Tie-break:
   - **0 live** → deliver durably to `threads_for(claude)` head (the most recent thread); the ask
     waits there, no liveness invented.
   - **exactly 1 live** → deliver there.
   - **>1 live** → the most-recently-active session, by `last_active_at` — the forward-only warmth the
     switchboard and MCP tool calls already bump (a measured signal, not thread-id order). This is the
     defined rule, not a guess: refusing on ambiguity would make the tool unusable for an agent who is
     a coworker on several threads (claude on Tlön + the machine thread), which is the normal case.

**Hole 2 (review) — the return path: how the answer gets home**

The first draft stopped at delivery to the peer and never said how the caller reads the answer — and
it cannot via existing tools: `get_messages`/`get_facts` are scoped to the connection's own thread
(identity rides the token), so a caller who isn't staffed on the peer's thread cannot poll it. The
answer must come back. So a consult is a **correlated ask/answer pair**:

- The ask lands on the peer's thread, authored by the caller's real identity, carrying `consult_id`
  and its `origin_thread_id` (the caller's thread).
- When the peer answers — a normal reply to the ask (`reply_to` the ask's message id) on its own
  thread — funes mirrors the reply **back to the caller's `origin_thread_id`**, tagged with the same
  `consult_id` and authored as the peer. It lands in the caller's own dossier/chatter; no cross-thread
  read tool is needed.
- The caller reads the answer on its OWN thread (its dossier) and can keep the consult going by
  `reply_to` on the mirrored message — which the mirror carries **forward** to the peer again.

**The mirror is a bidirectional bridge, keyed on `consult_id`, for the life of the consult** — not a
one-shot peer→caller hop. A follow-up the caller posts on its own thread mirrors forward to the peer;
 a follow-up the peer posts mirrors back to the caller. The mirroring rule is "any new message on
 either side's thread that replies within this consult is copied to the other side", until the consult
 closes. The one-way phrasing undercounted it.

**Echo guard (correctness, not polish):** a mirrored post is itself a `Channel.post`, so the mirror
must not re-fire on its own output — ask→mirror→mirror-of-mirror→… forever. Every mirrored message
carries a marker (a `mirrored` flag on the row, or keyed off which side authored it) and the mirror
skips anything already marked. Without this it is an infinite reactive-bridge loop.

This is the schema cost the first draft hid: the ask message needs `consult_id` + `origin_thread_id`
(a small correlation — a column or a consult table), so `consult_id` is a real correlation, not an
implied fiction.

**Single-writer + identity still hold**

- The call authenticates as the caller via the token → frame binds (caller_thread, caller_agent,
  caller_session). The caller never passes a thread id — only a peer agent name — so misdirection is
  unrepresentable.
- funes mediates BOTH writes (ask on the peer's thread, mirrored answer on the caller's) through
  `Channel.post`; no adapter writes cross-thread directly. Authors are always real identities.

**Two delivery modes, one contract**

- **Durable (works today):** the ask is a message on the peer's thread; the peer sees it on its next
  dossier refresh (or the switchboard's `@mention` wake if that lands). An offline peer finds it
  waiting, which is honest.
- **Live wake (the optimization, presence-gated):** when the switchboard is presence-gated, the
  delivered ask pokes the peer's live session (the `Funes.Switchboard` + `Funes.Mentions` machinery
  exists for exactly this). The contract is durable delivery; the wake is a latency improvement, never
  assumed.

**Boundary cost**

A `Consult` context (or `Channel`-adjacent functions) + the ask's `consult_id`/`origin_thread_id`
correlation and the mirrored-post marker, a new `Funes.MCP.Tool.ConsultPeer` component and the
`consult_peer` directTool, plus the answer path (the bidirectional, echo-guarded mirror). That is the
whole surface — and it is the reviewed, deliberate widening this file's history is for.

### 2c — Discoverability (the operator's "point at the surface" fix)

Whatever lands, it must be *nameable from inside Tlön*. Concretely:

- The **brief** should name the consult surface once it exists — a `You can ask a coworker with
  consult_peer(peer, …)` line, and `/consult`/`/fresh` as the in-session second-opinion commands, so a
  model never again improvises a `tmux send-keys`.
- The **coordinate-via-funes skill** should point at `consult_peer` and `/consult` as the escalation
  path, replacing the operator-keybinding routing that failed.

### 2d — Deferred, and why

Building A touches funes' boundary (`lib/funes.ex` exports) and the message schema (the ask's
`consult_id`/`origin_thread_id` correlation) — both deliberate by design, "the surface creeps only on
purpose, reviewed in this file's history." A live wake also needs the presence-gated switchboard, which
its moduledoc flags as not-yet. So the sequence is: (1) ship attribution (done), (2) get sign-off on
A's surface + schema widening (this review), (3) land presence-gating, (4) build `consult_peer` +
the answer mirror + name it in the brief/skill. This doc is step 2's artifact.

### 2e — Review checks (for the second set of eyes)

Before anyone builds this, verify each against the codebase — a `consult_peer` that *looks* right but
fights the token/session model is exactly what this pass is for:

- **Author / misdirection.** The consult must be authored by the CALLER's real agent identity, and the
  caller must never pass a thread id — only a peer *agent name*. If `consult_peer` lets a caller post
  to an arbitrary thread, or as the operator/peer, it breaks both the misdirection rule and the
  single-writer discipline. Reject.
- **Tie-break is a real rule, not a hop.** The target resolves over `threads_for/1` + live
  sessions; for >1 live, the most-recently-active session by `last_active_at` — NOT thread-id order,
  and NOT `live_session/2` used as if it were a lookup-by-agent. Verify the warmth signal is the
  measured `last_active_at`, and that an agent live on several threads gets a defined target.
- **Return path is a round-trip, not a one-way fire.** The ask must carry `origin_thread_id` + a real
  `consult_id` correlation, and the peer's reply must be mirrored back to the caller's own thread.
  If the caller would have to poll the peer's thread (it can't — `get_messages` is own-thread) or if
  `consult_id` has no backing schema, the round-trip is unfinished. Reject.
- **The mirror is a bidirectional bridge, not a one-shot.** A follow-up on the caller's side must
  mirror forward to the peer, keyed on `consult_id`, for the life of the consult — not just
  peer→caller once. A one-way implementation is incomplete.
- **Echo guard.** A mirrored post is itself a `Channel.post`; the mirror must never re-fire on its
  own output (ask→mirror→mirror-of-mirror→…). Verify every mirrored row is marked and the mirror
  skips already-marked rows. This is a correctness bug if missing, not polish.
- **Target filters by agent.** The per-thread lookup uses `live_session(thread.id, peer_id)` —
  never `session_for_thread/1` un-filtered, which could return a stray cross-agent session on the
  peer's thread and misroute the ask.
- **Single-writer.** Both the ask and the mirrored answer must go through `Funes.Channel.post` (or a
  new `Consult` context that itself calls the channel) — never a direct schema write from the tool.
  The new export must live inside the `lib/funes.ex` boundary, not widen it accidentally.
- **Presence honesty.** The tool must not claim the peer read, will answer, or is live. Delivery is
  durable; a wake is gated on presence-gating landing. Any "answered"/"read" claim is invented.
- **Offline degradation.** A consult to an agent with no live session must land durably on the most
  recent thread and be readable later — never a dropped message or a false failure.
- **Unknown/duplicate peer.** `peer` is `Staff.agent_by_name`. On an unknown or ambiguous name, refuse
  (like `CloseThread`'s missing-id refusal) rather than guess.

**Resolved after review (2026-08-17):**

- **Distinct kind in the peer's brief — BUILT.** The ask renders as "<caller> is consulting you —
  reply to answer" in the peer's chatter (both `Funes.MCP.Brief` and the pi `brief.ts`), and the
  `coordinate-via-funes` skill tells the peer to answer with a `reply_to` on the ask. Load-bearing:
  without the explicit reply affordance, the round-trip the bridge exists for wouldn't fire. No
  schema change — the message already carries `consult_id`/`origin_thread_id`; the renderer flags an
  ask as `consult: true`.
- **Auto-close on answer — REJECTED, stays parked.** The mirror is a bidirectional bridge for the
  life of the consult; auto-closing on the first reply would sever the caller's follow-up (nothing
  to mirror through). A consult is a conversation, not a request/response — "done" when it's done,
  like a Slack thread. If lifecycle is ever wanted, it must be explicit (a close verb) or
  inactivity-based, never first-answer.
