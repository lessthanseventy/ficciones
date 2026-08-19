# Aleph chat + attention layer — design

**Date:** 2026-08-19
**Status:** design (brainstormed with Andrew; Phase 1 shipped; architecture revised — see Revision B)
**Author:** claude-machine (Tlön), with Andrew
**Supersedes/extends:** `2026-08-15-aleph-tui-design.md`

> **Revision B (2026-08-19, after the answering-model investigation) supersedes the 3-space
> layout below.** Read Revision B at the bottom first — the space model changed (Sessions
> dissolves; Orbis & Tlön each get `chat` + `sessions` windows). The attention model, staffing,
> and reply→wake decisions above still hold; only the surface topology changed.

## Origin

Andrew typed *"i would like to test the new chat interface here. who am i talking to?"*
into the Tlön chat composer, started a fresh thread — and got silence. Diagnosis:
in Tlön the coworkers (pi-machine, claude-machine) are **hard-bound to one standing
machine thread**; a newly-created thread has nobody staffed on it and nothing spawns
onto it, so the message reached no agent. No reply, no "who's here," no way to see
anyone thinking.

The deeper story: **thread lifecycle and agent lifecycle are decoupled.** Aleph holds
two disconnected models of a conversation — a read-only chat view over funes
threads/messages, and a set of live agent PTYs bound to threads through a registry —
and the composer verbs only half-bridge them (`n` creates+spawns+binds; `c` posts to
the focused thread and binds nobody).

## The herdr lens

v1 of this workspace was built *on top of* herdr and shoehorned Tlön onto it — messy.
The better trade is the reverse: **aleph is the spine, and herdr's attention model is
brought in conceptually.** Aleph is the only process that can build it, because it holds
both the live PTYs and the funes dossier in the same hand.

What we want from herdr, specifically:

- **What is this agent doing?**
- **What do I need to be looking at?**
- **Who's stuck and needs me to respond?**

## Goals

From Andrew, the chat interface should let him:

1. **Start** a new thread and choose who staffs it.
2. **Reply** into a particular thread and have the right agent actually wake.
3. **See** who's on each thread, what they're doing, and who's blocked on him.
4. **Jump** to a thread's live session terminal in one motion.

## Non-goals (YAGNI)

- No new persistence store — funes remains source of truth.
- No re-ordering the chat by priority as the default (chat stays chronological).
- No desktop/OS notifications in this pass (tracked separately; see herdr-notifications memory).
- No classification/moderation of message content in aleph.

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Staffing on thread-create | **Pick who joins** — explicit agent picker |
| 2 | State-source for attention | **Fuse** terminal PTY motion + funes semantic signals |
| 3 | Chat ordering | **Slack-style**, newest at bottom (default); attention-sort a toggle |
| 4 | Attention home | **Left rail** — repurpose the `SETTINGS` panel into a `COWORKERS` roster |
| 5 | Per-coworker driver/config | **Folds into each coworker row** (collapsed = status, expanded = config) |
| 6 | Reply → wake | **Unified wake resolver**; bare reply wakes the **thread lead**, @-mention directs |

## Architecture — three layers

**Layer 1 — funes is the source of truth.** Threads, staffing (`Staff.assign`), and
semantic signals (`raise_question`, `raise_issue`/blocker, `record_done`, todos,
`Presence.warm?`) already exist. The attention model *reads* these; it does not invent
a new store.

**Layer 2 — aleph attention engine (new).** A derivation layer that fuses two inputs
into a single per-coworker attention state:

- **Terminal motion** (herdr's motion-sense): watch each embedded PTY. Output
  streaming → *working*; quiet at a prompt → *idle*.
- **Funes signals** (semantic-sense): an open question/blocker addressed to the
  operator → *needs you*; `record_done` → *done*; recent MCP activity → *alive*.

Fusion is what makes it robust: motion catches "working right now" that agents never
self-report; funes catches intent that motion can't distinguish (waiting-on-you vs
just-finished).

**Layer 3 — surfaces.** The `COWORKERS` roster (glance), the chat (conversation), and
the Sessions terminals (deep-dive).

## The attention state model

Every staffed coworker carries exactly one state:

| State | Meaning | herdr question answered |
|-------|---------|-------------------------|
| 🔴 **Needs you** | Asked a question, raised a blocker, or hit a permission gate — turn parked on the operator | "Who's stuck and needs me to respond" |
| 🟡 **Working** | Actively producing output right now (PTY motion) | "What is this agent doing" |
| 🟢 **Done** | Delivered / `record_done`, awaiting the operator's read | "What do I need to look at" |
| ⚪ **Idle/cold** | Staffed but asleep, nothing pending | (background) |

## Surface 1 — the COWORKERS roster (repurposed SETTINGS panel)

The bottom-left rail panel stops being model-driver config and becomes a **coworker-first
attention glance**, always visible regardless of which thread is being read:

```
COWORKERS
🔴 claude-machine   needs you · "which agent joins?"      #1 Tlön
🟡 pi-machine       working · editing mention.ex           #4
🟢 kimi             done · 3 files, check #7               #7
⚪ deepseek         idle                                   —
```

- **Dot** = attention state. **Verb-phrase** = "what it's doing" (fused). **Tag** = its thread.
- 🔴 rows draw the eye — the "who needs me" answer sits in the periphery at all times.
- **Selecting a row** focuses that coworker's thread and is the one-key hop to its live
  terminal (Goal 4).
- **Expanding a row** reveals its config — driver/model (e.g. `ollama-cloud/glm-5.2` and
  alternatives), mandate, permissions — so config lives with the thing it configures
  (Decision 5). Collapsed = status; expanded = settings.

This keeps the roster coworker-first (herdr) while the chat stays thread-first — two
lenses on the same funes state, neither fighting the other.

## Surface 2 — the chat

- **Slack-style, chronological, newest at the bottom** (as `ac3f69c` already built it).
- **Attention-sort is an optional toggle**, off by default — the roster carries priority,
  not the chat.
- **Start a thread** → agent picker (Decision 1): choose who staffs it; they are
  `Staff.assign`ed and spawned onto *that* thread (not the standing machine thread), and
  woken with the opening message. This is the fix for the origin silence.

## Surface 3 — reply → wake (the unified resolver)

Today two wake paths exist and neither covers "reply to an arbitrary thread":

- Tlön/tmux: `Aleph.Mention.route` → `tmux send-keys` into a **statically-named** window,
  only on @-mention.
- Project sessions: funes switchboard → `Aleph.Arbiter.wake` for `Aleph.Terminal` PTYs.

**Unify them.** On any post to thread N: look up who is staffed (funes `Staff`), resolve
each to its live terminal/window, and inject the turn. One "wake whoever's on this thread"
resolver behind both backends.

Directing rule (Decision 6):

- **Bare reply** wakes the thread's **lead/primary** coworker — so someone always answers,
  killing the silence trap.
- **@-mention** overrides and directs the turn at the named coworker.
- Scales from one staffed coworker to many.

## Implementation surfaces (from the code map)

- `lib/aleph/cockpit.ex` — the GenServer brain: effects (`create_thread`, `post_message`,
  `enter_or_spawn`, `spawn_onto`), coworker spawning, mention delivery, tmux plumbing.
  New: attention-engine tick, staffed-thread wake resolver, roster render data.
- `lib/aleph/keymap.ex` — add the agent-picker step to thread-create; reply-to-focused verb.
- `lib/aleph/mention.ex` — generalise beyond the static `@base_coworkers` map to any
  staffed handle; feed the unified resolver.
- `lib/aleph/sessions.ex` — `thread_id → terminal` registry; extend to resolve any staffed
  coworker's window/terminal for waking.
- `lib/aleph/arbiter.ex` — the funes→aleph wake seam; one of the two backends behind the
  resolver.
- Panels: replace `settings` panel with a new `coworkers` roster panel; `conversation.ex`
  (chat) gains the optional attention-sort toggle; `roster.ex`/`status_bar.ex` feed state.
- funes reads used: `Staff.roster`/`assign`, `Presence.warm?`, `Dossier` questions/blockers/
  done, `Channel.post`/`open_thread`.

## Open questions / follow-ups

- **"Thinking" precision.** PTY motion is a good proxy for *working*; do we ever need a
  finer turn-start/turn-end signal from the harness, or is motion enough? (Start with motion.)
- **Thread "lead" definition.** Who is the lead when several are staffed — first staffed,
  operator-designated, or funes `lead`? (Lean on funes `lead`.)
- **HABITS panel noise.** Separately, pi-machine chatter shows in HABITS PENDING because the
  coworker literally calls `propose_habit` for non-habits. Fix is coworker prompt/tool
  gating, not the aleph render path. Out of scope here but noted.
- **Notifications.** OSC 9/777 "agent waiting on you" via ghostty — deferred (herdr-notifications).

---

# Revision B — space architecture (2026-08-19)

After investigating how a Tlön coworker actually answers on a thread, two things forced a
topology change.

**The answering-model finding.** A coworker posts to the thread its token is bound to
(`FUNES_THREAD`); `post_message` takes no thread arg — misdirection is unrepresentable by
design. `switch_thread` exists but is only the *signal half* (mints a new token; the adapter
re-handshake that would consume it isn't built), and pi doesn't even have the tool. So an
agent answers on thread N only if it was **spawned bound to N** — the per-thread identity mint
`Spawn.join(N, agent)` that the old Sessions space already does (`spawn_onto`), but that Tlön
never wired in. → **A new chat thread gets its own session (Andrew's default). Warm-rotating an
idle agent onto a new thread (the optimization) is deferred until the `switch_thread` adapter
half exists.**

**The topology change (Andrew).** *Sessions as its own space is overloaded.* Dissolve it. Give
**each domain its own chat + its own session manager**, so the scope wall is total.

## The revised spaces

Two spaces, symmetric, each backed by its own tmux session with **two windows**:

- **Orbis** (project / real) and **Tlön** (machine / dogfood). **No standalone Sessions space.**
- Per space:
  - **`chat`** — the thread front-door: browse threads, start new ones (pick who joins),
    post/reply. (Today's `machine_chat`, generalized; Orbis gets one too.)
  - **`sessions`** — a **session-manager index**: the space's threads + each one's session
    status (staffed? live? warm? working / stuck?); selecting a row opens that session's
    terminal; spawn / attend / kill from the index. NOT a bare tab-strip of PTYs — an index
    that *opens into* terminals.
- **Left rail stays global** — SPACES picker, the **COWORKERS attention roster** (who's working /
  who's stuck, across both spaces), STACK / HEALTH.
- **Two axes of movement:** *within* a space, flip `chat ↔ sessions`; *across* spaces, switch
  `Orbis ↔ Tlön`.

## Roster vs. index (they share one state)

The left-rail **COWORKERS roster** is the *global ambient glance* ("who needs me, anywhere").
The per-space **`sessions` index** is the *local workspace* you act in (attend / spawn / kill
this space's sessions). Both derive from the same fused attention state (funes signals + PTY
motion) — one is a readout, one is a control surface. The index must not just duplicate the
roster; it adds per-thread session control the roster doesn't have.

## How a chat thread becomes an answered thread (the core mechanic)

1. In a space's `chat`, operator starts a thread and **picks who joins**.
2. `Channel.open_thread(scope)` + `Funes.Staff.assign(thread, agent)` (the lead) +
   spawn that coworker as a **session bound to thread N** (`Spawn.join(N, agent)` → a PTY whose
   `FUNES_THREAD=N`). The session surfaces in this space's `sessions` index.
3. The coworker, born on N, answers **on N** via its own token — no funes changes, no
   `switch_thread` glue.
4. `chat` shows the conversation + who's responding (roster state); "jump to the session" =
   flip to `sessions` and open that thread's terminal.

## Revised phasing (supersedes the plan's Phase 2–4 headings)

- **B1 — the core mechanic:** chat composer staffs + spawns a coworker session bound to the new
  thread, so "type in chat → chosen coworker answers on that thread" works end to end. Includes
  the `wake_mentions`→`route/2` bridge finding from the plan.
- **B2 — the `sessions` index window** (index-opens-into-terminals) per space.
- **B3 — dissolve the Sessions space; give Orbis its own `chat` + `sessions`** (symmetry).
- **B4 — the COWORKERS attention roster + fused state** (was Phase 3), feeding both roster and
  index.
- **Deferred — warm rotation** (`switch_thread` adapter half) once cold-spawn cost bites.

## Open (to detail during B1 planning)

- **How "pick who joins" works in the chat** — an explicit picker step, or `@handle` in the
  composer message doubling as the staffing selector, or a default with override.
- **Where the spawned session PTY lives** — a tmux window in the space's session vs. an embedded
  ghostty terminal the index opens; ties into what the `sessions` index renders.
- **Scope/rendering assumptions** that today hard-code one machine thread
  (`Channel.machine_thread/0`, the LOGBOOK, `composer_thread_id`) need revisiting once threads
  are many and per-thread-staffed.
