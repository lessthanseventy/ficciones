# Tlön episodes: coordination & cost-aware session rotation

**Date:** 2026-08-18
**Status:** design agreed (brainstormed with Andrew), NOT yet implemented
**Builds on:** the machine-chat episode UI + composer (commits `2adad4c`, `ac3f69c`, `d946487`).

## The picture

The Tlön dogfood surface is a **machine-scoped Comms**: the same Chorus feed + composer +
mention-wake + notifications the cockpit's Comms space has, filtered to `scope: machine`. An
**episode = a funes thread** (title, open/closed, spans sessions). The chat tab is the interactive
front (tab 1): a bottom **composer** kicks off a new thread/task, the feed is the episodes
newest-at-bottom (Slack-style), `@`-mentions wake coworkers.

**Future north star (not now):** Comms becomes scope/folder/project-aware — spin up a scoped Comms
view anywhere; "Tlön" is just the first instance.

## What's already built

- `Funes.Channel.machine_threads/1` — machine-scope threads as blocks.
- `Aleph.Transcript` — pure renderer (episodes, participants, open/closed), a `Panel`.
- `Aleph.MachineChat.{Host,Loop}` + `mix aleph.machine_chat` — the tab: episode list, browse
  (`j/k`/`z`), and a **composer** that opens a machine-scope thread, posts as the operator, and
  wakes `@`-mentions by `tmux send-keys` (reusing pure `Aleph.Mention`). chat seated as tab 1.

## The open piece: rotation + session lifecycle

Today an agent's funes connection is bound to ONE thread; `post_message` only hits that thread
("no tool takes a thread parameter"). So a woken agent's REPLY lands in its own thread, not the
episode it was summoned to. Closing that loop is the remaining work.

### Rotation = re-bind + dossier catch-up (never `/resume`)

To move agent X onto episode #N:

1. **Prefer a warm session.** If X already has a live session, re-bind its funes connection to #N
   and inject an *appended* catch-up turn. The agent's LLM KV-cache stays warm (append-only prefix)
   — no cache bust. This is the default whenever a session is alive.
2. **Cold-start seeds from the DOSSIER, never the raw transcript.** When X has no live session,
   spawn one on #N and seed it with #N's `get_dossier` brief (FACTS · UNKNOWNS · BLOCKERS · TODOS ·
   DONE) — a few hundred tokens of curated state. A `/resume` of the whole history is the
   cache-busting wall we explicitly avoid.
3. **Only the funes binding moves; the warm LLM context is left alone.**

Funes already has the primitives: live-session tracking (`register` / zombie guard /
`session_for_thread`) answers "is there a warm X?", and `get_dossier` is the catch-up brief.

### Session lifecycle: hybrid keep-warm

- **Warm while active.** Anthropic's prompt cache refreshes on every use, so an actively-working
  session never goes cold — keep it.
- **Idle-release after `cache_ttl − safety`.** Release a session that's been idle for just under its
  cache TTL, so we let it go right as the cache would expire anyway (releasing an about-to-be-cold
  session costs nothing; holding a cold one is pure waste). Config knob keyed to the session's TTL:
  ~4 min for the default 5-min cache, ~55 min for the 1-hour TTL.
- **Re-wake from the dossier** when an idle episode reheats — same cheap cold-start path as (2).

Net: never lose warm cache we could reuse; never pay to hold a cold session; never `/resume`.

### The new funes/adapter surface

- **DONE — `switch_thread` funes MCP verb** (`993753f`): the fourth cross-thread verb. Mints a token
  bound to `{thread_id, this agent}` via `Spawn.mint_for` and returns it. Server-side half; tested.

- **The hard part is the CLIENT re-bind, and it's more involved than "re-handshake with the returned
  token" (corrected after reading the adapter).** In pi there are TWO funes connections sharing one
  token: the manos extension's `FunesClient` (`mcp.ts` — register/dossier/capture) and **the model's
  own native MCP client** (`mcpServers.funes` in `flake.nix`), which is the one the agent's
  `post_message` rides. That native client authenticates via a **`!command` headers helper**
  (`scripts/funes-cli.sh bearer`) that mints a fresh token from the **static `FUNES_THREAD` env** on
  each connect — it never sees tool results, so returning a token from `switch_thread` does nothing
  to it. Also: `switch_thread` is not in that client's `directTools` allowlist, so the model can't
  even call it yet.

  So a live re-bind of the model's posts needs ALL of:
  1. add `switch_thread` to `mcpServers.funes.directTools` (flake) so the model can call it;
  2. make the headers helper mint for a **mutable** thread source (a per-pane file), not static
     `FUNES_THREAD`, so a switch changes what it mints for;
  3. on `switch_thread`, write the new thread to that source AND force the native client to
     **reconnect** (it only re-runs the headers helper on a fresh connect — a held session won't
     re-mint). How to force that reconnect from inside pi is the open unknown to probe next.
  The warm pi process/context is untouched throughout — only the funes binding + token move.

- **Cockpit rotation policy:** on an episode needing agent X, consult funes for a warm X, then
  switch-thread + inject dossier-catch-up, or spawn+dossier if cold. Idle-release on the timer.
- **`machine_thread/0` ambiguity:** with many machine threads, decide what the cockpit's
  logbook/chatter/composer key off (likely the focused episode, not "the latest open machine").

## Build order (when we pick this up)

1. ✅ **DONE (`993753f`)** — `switch_thread` funes MCP verb (mint token for the target thread).
2. **The client re-bind** (the real work — see "the hard part" above): `directTools` += switch_thread;
   headers helper mints from a mutable per-pane thread source; on switch, update it + force the
   native client to reconnect. **Probe first:** how to force pi's native MCP client to re-handshake
   mid-session. This is the gate for everything below.
3. Dossier-catch-up injection (a turn carrying `get_dossier(#N)`), reused by warm re-bind and cold
   spawn.
4. Cockpit rotation policy + the idle-release keep-warm timer (config knob for the window).
5. Resolve `machine_thread/0` → focused-episode semantics for the other Tlön panels.
6. The coworker mandate/habit: open a thread per topic, `close_thread` on agreement, reply on the
   thread you were switched to.

## Housekeeping (pending)

- Seed data: fabricated "andrew" episodes + two throwaway test threads in the `.dev` db — leave /
  relabel / delete (Andrew's call).
