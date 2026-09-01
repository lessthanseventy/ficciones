# Per-thread agents: leaves, a leader-of-leaders, and a harness-agnostic lifecycle

> **SUPERSEDED (2026-08-31)** by `2026-08-30-orchestrator-cockpit-plan.md` (Slice 4) and
> `2026-08-31-lead-as-manager-coordination-design.md`. The "leaf / leader-of-leaders" vocabulary is
> retired: a worker thread is a **child thread** (`thread.parent_thread_id`), a leader is a **lead**,
> and the "leader of leaders" is **tertius the orchestrator**. The harness-agnostic lifecycle and
> per-thread-worktree ideas here landed as Slice 4 (`Server.Worktree`, `staff_child`, `assign_lead`).
> Kept for lineage; do not build from this.

**Date:** 2026-08-22
**Status:** SUPERSEDED — see banner above (was: design, validated in brainstorm)
**Context:** follows the machine-chat staffing fix (`e14dfd6`) and the worlds/orbis reshape
([[2026-08-21-worlds-orbis-reshape-design]], [[2026-08-19-aleph-chat-attention-design]]).

## Problem

A machine-chat thread is meant to be a **leaf** with its **own lead**. Today only a
`claude_code` (builder) lead gets a real per-thread process — the cockpit spawns a dedicated
`t<id>` tmux window and injects the opening turn (`Aleph.Cockpit.ensure_thread_session`). A
pi-harness lead (surveyor/reviewer/planner) gets **no** window: the wake routes to the one
standing pi, so a second thread's turn lands in the first thread's context. That is the
isolation gap the staffing fix exposed but did not close.

Two things are needed:

1. **Per-thread leads for every harness**, not just claude.
2. A **harness-agnostic** lifecycle so a lead can be pi, claude, codex, gemini, … chosen by
   role and environment — without leaking the choice into the routing/spawn machinery.

## The model (already the intended design)

`tertius`'s own system prompt (`profiles.ex`) states it verbatim: tertius is the *"leader of
leaders"*, its home is the **root** machine thread, it does **not** do leaf work, and *"each
leaf has its own lead."* Its job is synthesis — read across the leaves (`machine_overview`)
and keep the root thread a current rollup of what's in flight / stalled / blocked / conflicting.

- **Leaf** = one work thread, one lead worker. Enforced by the data model: `thread.agent_id`
  is a single lead per thread.
- **Root thread** = tertius's home. Self-heals on restart: the center coworker's spawn
  opens/finds the root thread and tertius rebinds (`capture_standing_thread_id`).

## Routing: who leads a new leaf

Swap the dumb static default (`Staffing.default_coworker/1`, builder-else-first) for
intent-aware routing. Reuse the existing `pick_coworker` shape (mention wins, else default):

- **You @-mention a coworker → that coworker leads, directly.** No tertius hop — you already
  decided. Fast path.
- **You don't → tertius triages** the thread text and assigns the right specialist archetype
  (review → reviewer, plan/tickets → planner, build → builder, question → researcher).

Keep two ideas distinct:

- **Routing** (who leads): only *unrouted* threads go through tertius. An explicit
  `@planner-machine` must not pay a classification hop.
- **Vantage** (who sees): tertius watches **every** leaf via `machine_overview` and rolls them
  up regardless of how each got its lead. So "everything through one place" holds for oversight
  without making tertius a bottleneck on the fast path.

tertius must **never** be a leaf lead — it is the meta agent. The routing default therefore
excludes the surveyor/meta archetype; a world with no worker archetype in its roster is a
misconfiguration (this is what produced the degenerate `[surveyor tertius]` roster).

## The abstraction: coworker = archetype × harness-binding × model

The pillar. A coworker is three separable things:

- **Archetype** — the role: prompt, tools, permissions (surveyor / builder / reviewer /
  planner / researcher). Backend-agnostic.
- **Harness binding** — *how* it runs: `claude_code | pi | codex | gemini`. Resolved **per
  environment**.
- **Model** — the driver, already overridable per coworker (`Config.coworker_model`).

Today the archetype hardcodes the harness (`builder: harness: :claude_code`, others implicitly
pi). Lift the harness out into an environment-resolved binding.

### Environment resolves the harness (the ToS rule)

The same archetype runs under different harnesses depending on where aleph runs:

- **Home** (personal Anthropic subscription): Anthropic-model archetypes bind to
  **`claude_code`** — the official harness. Driving a personal Claude subscription through a
  third-party harness (pi) risks the account; do not.
- **Work** (API keys / billed): the same archetypes may bind to **`pi`** (or codex/gemini).

Rule of thumb baked into resolution: **Anthropic-subscription models → `claude_code`;
everything else / work API → `pi`/`codex`/`gemini`.** Environment is a single config signal
(env var or config key), not per-coworker guesswork. See [[claude-plan-preferred-bucket]],
[[pi-nix-bun-binary]].

### Harness-driver interface

The lifecycle talks to a small, uniform contract; each harness implements it:

```
spawn(profile)            -> handle      # start a process/window for a lead
inject_turn(handle, text)                # deliver a turn (send-keys today; API later)
reset_context(handle)                    # clear the conversation, keep the process warm
resume(handle, leaf)                     # reattach a leaf's OWN prior conversation
teardown(handle)                         # stop and release
```

`claude_code` and `pi` implement `inject_turn` via tmux `send-keys` (the current path);
API-only backends (codex/gemini) may implement it as a request. Pool-vs-fresh becomes a
**policy over this interface** and can differ per harness.

## Lifecycle: a warm pool, rebind by clearing (not resuming)

Target model: a bounded **pool** of warm workers per (harness, archetype), rebound to leaves on
demand. Fresh-per-leaf is the degenerate case — a pool of size 1 that never rebinds.

The sharp rule — **rebind = `reset_context` + re-hydrate from the funes dossier, never
`resume`-onto-a-new-leaf.** Resuming a pooled worker onto a *different* leaf re-introduces the
exact context-bleed bug we just fixed. `resume` is reserved for returning to a leaf's **own**
agent to continue **that** thread — a "for whatever reason" escape hatch, not the hot path.
See [[tlon-episodes-and-rotation]].

Pool sizing / eviction / keep-warm-by-cache-TTL is a **later** policy. Start simple
(fresh-per-leaf) and add pooling when process/latency cost bites — YAGNI.

## Naming: human names, not `t<id>`

`t<id>` exists only so the code can find a window; it should never be what you stare at.

- **Human name = the thread title, everywhere you look** — leaves list, window bar, tertius's
  rollup. Leaves must stop surfacing `t<id>`.
- **tmux window name = `<archetype>-<title-slug>`** — e.g. "let's review this PR" led by the
  reviewer → `reviewer-review-this-pr`. Readable in `tmux list-windows`; shows role and subject.
  Slugify, truncate ~24 chars, add a small disambiguator only on collision.
- **Routing stops parsing the name.** The cockpit keeps a `thread_id → window` map so the
  window can be named anything human-friendly without breaking wake/delivery. The stable
  routing key stays the numeric thread id.

## UI priority

The **root thread (tertius's rollup) is the primary surface.** Dropping into a leaf's raw
session is the rare escape hatch (alongside resume-into-an-old-leaf). If the rollup works, you
should rarely need a leaf terminal — that is the thesis, and it sets panel priority: root
rollup foreground, leaf terminals a drill-down.

## What exists vs what to build

Already there:
- `thread.agent_id` single lead per thread.
- Per-thread `t<id>` spawn + opening-turn injection **for claude leads**
  (`ensure_thread_session`, gated on `claude_launched?`).
- `machine_overview` for tertius's cross-leaf read; tertius role prompt.
- `Staffing.pick_coworker` (mention-else-default); `Config.coworker_model` per-coworker.

Gaps to close (the build):
1. **Per-thread spawn for pi leads** — generalize `ensure_thread_session` beyond
   `claude_launched?`.
2. **Harness abstraction** — lift harness out of the archetype into an environment-resolved
   binding + the driver interface.
3. **tertius triage** — classify an unrouted thread → archetype; assign/spawn its lead.
4. **Roster hygiene** — worlds carry worker archetypes; default lead never resolves to the
   meta surveyor.
5. **Human window names + thread_id→window routing map.**
6. **Pool + clear-not-resume rebind** (later; fresh-per-leaf first).

## Suggested slice order (incremental, each shippable)

- **Slice A — pi leaves get their own window.** Drop the `claude_launched?` gate so a pi lead
  spawns a `t<id>` session and takes its opening turn. Closes the core isolation gap. No new
  concepts. *(Biggest bang, smallest change.)*
- **Slice B — roster hygiene + worker-only default.** Put worker archetypes back in the world
  roster; make the routing default pick a worker, never the surveyor. Makes Slice A actually
  staff the right kind of agent.
- **Slice C — human window names + routing map.** Name windows `<archetype>-<slug>`; route via
  a `thread_id → window` map instead of name parsing.
- **Slice D — harness binding + driver interface.** Lift harness out of archetype;
  environment-resolved binding with the Anthropic-sub→claude_code rule; the uniform
  `spawn/inject_turn/reset_context/resume/teardown` contract. Enables non-pi/claude backends.
- **Slice E — tertius triage.** Classify unrouted threads → archetype and assign the lead.
- **Slice F — warm pool + clear-not-resume rebind.** Only when cost/latency justify it.

## Open questions / YAGNI

- **Environment signal** — how aleph learns home vs work (env var vs config key). Assume a
  single config key for now.
- **Triage mechanism** (Slice E) — a tertius tool call vs a cheap classifier vs keyword rules.
  Decide when Slice E starts; keyword rules may be enough.
- **Pool sizing / keep-warm** (Slice F) — deferred; keyed to cache TTL per
  [[tlon-episodes-and-rotation]] when built.
- Codex/gemini `inject_turn` shape (send-keys TUI vs API) — decide per backend when first added.
