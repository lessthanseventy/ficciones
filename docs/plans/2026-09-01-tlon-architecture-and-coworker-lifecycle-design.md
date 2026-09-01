# Tlön architecture + coworker lifecycle — design

**Date:** 2026-09-01
**Status:** designed; shipped items noted, the rest sequenced for later builds
**How this came up:** building the per-thread reply input (below) surfaced that posting a
reply produced no coworker response. Tracing it went two levels deep — the coworker was
offline, *and* the cockpit runs on an unseeded scratch DB behind a second server instance.
Andrew: "I'm starting to see this become usable, so I want to make sure we aren't setting bad
patterns." This doc captures the whole thread so the architecture can be built deliberately.

---

## 1. Shipped this session

Three self-contained pieces, tested and committed to `main`:

- **Persistent per-thread reply box** (`54f1092`, fix `2db0f5b`). Opening a thread focuses a
  persistent `:reply` input; the `c` verb is retired from the chat flow. The bottom band morphs
  with the center step — `NewThread` in the LIST, `Reply` in a CONVERSATION, read off the same
  `thread_stack.opened` the center uses. Design: `2026-09-01-per-thread-reply-input-design.md`.
  Live-verified (a reply posted to thread #7).
- **NOW activity backfill** (`7f197e8`). The activity ring is in-memory and was seeded empty, so
  NOW read "no activity yet" after every cockpit restart. It now backfills from
  `Server.Board.recent_activity/1` (recent messages + facts + events, merged newest-first),
  guarded so a not-yet-up server yields an empty ring.
- **Test hygiene** (`aa7530c`). `Crew.spawn` materialises a profile into `~/.pi/profiles` as a
  side effect, which failed under a read-only home and polluted the real dir. `test_helper` now
  points `PI_CODING_AGENT_DIR` at a throwaway dir once, hermetic and async-safe. Whole console
  suite green (874/0).

These are done. Everything below is designed, not built.

## 2. The problem the reply work uncovered

Posting a reply is wired correctly end-to-end: `Channel.post` broadcasts `{:message_posted}` →
`Switchboard.Runner` → `Switchboard.deliver` → wake the thread's lead. But nothing responded,
for two independent reasons:

1. **No live coworker.** CREW showed `0/6 live`. The switchboard only wakes a **warm** session
   and, by design, never auto-spawns a *cold* one (waking pokes a real, paid agent — the
   "resumed an old thread and burned my whole allotment" guardrail). With nobody warm on the
   thread, the message stays `:pending` until a session appears and `drain/0` delivers it.
2. **The cockpit runs on an unseeded scratch DB behind a second server.** Threads there are
   never *staffed* (no lead assigned), so `Switchboard.maybe_spawn_absent/1` — which *would*
   open a pane for an absent lead — has no `agent_id` to act on and no-ops.

## 3. The two-brain problem (current state)

The console app **embeds** the server (`{:server, path: "../server"}`), so `console:run` boots
its own in-process `Server.Repo`. The result is two independent brains:

| | Embedded (cockpit) | Systemd (`tlon.service`) |
|---|---|---|
| Port | :4041 | :4040 |
| DB | `modules/server/.dev/tlon.db` | `~/.local/share/tlon/wb.db` |
| Lifecycle | dies with the cockpit | always up |

One good property today: the cockpit **and the coworkers it spawns** share the embedded brain
(spawned agents get `TLON_MCP_URL=…:4041`), so they're consistent *with each other*. The bad
pattern is that (a) the daily driver runs on a DB literally named `.dev/` that nothing seeds —
the direct cause of the unstaffed threads — and (b) anything pointed at the :4040 service is
invisible to the cockpit and vice-versa. As Tlön dogfoods itself there is no real dev/prod
split; "which brain am I in?" is a footgun.

## 4. Target architecture — one always-up server, cockpit as client

**Decision (Andrew):** the future wants a **web UI (Phoenix/LiveView)** and **persistent Oban
jobs**. Both need a server that outlives any TUI, so the embedded model is wrong. The target:

- **The always-up systemd server is the single source of truth** — it owns the DB, MCP, and
  later the web UI and Oban. One seeded real DB. The `.dev` DB is **test-only**.
- **The cockpit becomes a client of it**, not an embedder. Cleanest boundary is
  distributed-Erlang RPC into the server node (`:erpc.call(server_node, Server.Channel, …)`),
  which keeps today's in-process call ergonomics while one process owns the DB. Pointing two
  BEAM nodes at the same SQLite file instead just buys `database is locked`.
- **The two-brain split is retired** — there is one server, one DB, one MCP endpoint; the
  cockpit and every coworker connect to it.

**Consequences, accepted deliberately:**

- The server outlives the cockpit — which is precisely what enables the web UI and Oban.
  Closing the cockpit no longer stops background citizens.
- This is a real refactor, not a config flip: the console app must stop embedding `:server`
  and route its reads/writes over the RPC boundary. It should be its own plan.
- **SQLite → Postgres is likely** once Oban (Postgres-native) and a concurrent web UI arrive.
  Not a decision for now; it reinforces the same "always-up server owns the data" direction, so
  it doesn't change the target — build the client boundary first, migrate the store later.

## 5. Coworker lifecycle — on-demand, fresh-seed on cold

**Decision (Andrew):** a coworker should come online **on-demand when you post**, and a cold
lead should get a **fresh context seeded from the dossier**, never a `/resume` of a huge one.

- **Trigger:** an operator post to a thread (the reply path). An explicit post is intent to
  engage, so it may spawn where a background backlog drain stays restrained.
- **Warm lead** (a live session inside the warmth window): **wake it** — a cheap resume, the
  cache is still hot. This is today's `recipients/1` → `waken` path, unchanged.
- **Cold or offline lead:** spawn a **fresh** session seeded with `Board.brief(thread)` — the
  dossier catch-up that already exists as "the same one-call read that briefs a re-entering
  session from the dossier rather than the transcript." Never re-ingest the old transcript.
  This is the "rotation via re-bind + dossier catch-up, never `/resume`" idea, made real.
- **The cold dead-zone (an INTENTIONAL guardrail today, to be inverted).**
  `Switchboard.has_live_session?/2` only checks `ended_at IS NULL`, so a *cold* session (stale
  `last_active_at`, not ended) counts as "live": `recipients/1` excludes it (too cold to wake)
  **and** `maybe_spawn_absent/1` skips it (a session exists). An existing test locks this in —
  *"a lead with a live (even cold) session is not auto-spawned — no zombie double-spawn."* So
  cold-silence is a designed choice, not a bug. Andrew's decision inverts it into a **rotation**:
  a cold lead's stale session is retired and a fresh one takes its place.
- **Rotation = relaunch-in-place, not a new pane (Andrew 2026-09-01).** Don't kill the pane and
  spawn a fresh one — reuse the existing pane: `tmux respawn-pane -k` at the cold session's
  `pane_ref` kills the stale process and boots a fresh harness in the SAME pane, seeded from
  `Board.brief`. The pane keeps its identity (window name, `@funes_thread` tag, bar slot); no
  orphan, no teardown sweep, no new "archived" session state — the session just re-binds. Fall
  back to a brand-new pane only when the cold session has no `pane_ref` to reuse.
- **CORRECTION (2026-09-01) — the arbiter IS wired.** An earlier note here wrongly claimed no
  backend was configured (a bad grep). In fact `config :server, :arbiter, Console.Arbiter` is set
  unconditionally (console `config.exs`), `start_switchboard: true`, and `Console.Arbiter` actuates:
  `wake/2` writes the prompt into the session's embedded ghostty terminal; `spawn/1` calls
  `Console.Sessions.spawn_harness`. So the switchboard DOES poke a real backend — the cold-dead-zone
  fix is NOT blocked; it's directly implementable. (Because sessions are ghostty terminals the
  console owns, not tmux panes, the "rotation" is `Sessions` relaunching the harness for the thread,
  not a literal `respawn-pane -k` — same intent, console-owned mechanism.)
- **Prerequisite — staffing.** `maybe_spawn_absent/1` needs `thread.agent_id`. Bootstrap already
  seeds the workspace ROSTER (`tertius`/`hronir`/`reviewer`/`planner`), but roster entries are not
  registered as `Agent` rows nor assigned as thread leads — that gap is WS1.1.

Cost stays governed: warm → cheap resume; cold → one relaunch-in-place, brief-seeded (bounded
context), only on an operator post, never a background auto-spawn of an idle roster.

## 6. Seed-on-boot — the immediate unblock

Independent of §4/§5 and needed in **every** future (client or embedded, SQLite or Postgres):
an **idempotent world + roster seed** that runs on server start and creates the workspace world
and its coworker roster if absent. This is the root-cause fix for `0/6` / unstaffed threads —
once threads have a lead, `maybe_spawn_absent` can fire and the on-demand lifecycle works. The
seed logic is reusable regardless of where the DB ends up; only its target DB is config. (Prior
note: "durable fix — seed in aleph:run — still TODO." This closes it.)

## 7. Sequenced build plan

Ordered by unblock value; each is a shippable chunk.

1. **Seed-on-boot (§6, WS1.1).** Register the roster as `Agent` rows + assign thread leads on
   boot (the workspace roster is already seeded; the Agent/staffing link is the gap). Unblocks
   `maybe_spawn_absent`'s precondition. Smallest, future-proof.
2. **Cold-rotation lifecycle (§5).** Invert the intentional cold guardrail: when the lead's only
   session is cold, END it (so no zombie) and let the switchboard spawn a fresh one through the
   already-wired `Console.Arbiter` (→ `Sessions.spawn_harness`, brief-seeded). Flip the "no
   auto-spawn over a cold session" test to "a cold-only lead is rotated." Verify post → rotation →
   reply. Directly implementable — the arbiter is wired.
3. **Client/server split (§4).** Stop embedding `:server`; the cockpit RPCs into the always-up
   node; retire the :4041/.dev second brain; `console:run` targets the real seeded DB. The biggest
   change, its own plan.
4. **Web UI + Oban (§4, later).** Phoenix/LiveView over the same server; Oban for scheduled +
   persistent jobs. Likely triggers the SQLite → Postgres migration. Future work, own designs.

## 8. Open questions (deferred)

- **Postgres migration timing** — build the RPC client boundary on SQLite first, migrate the
  store when Oban/web-UI land, or migrate the store first? Leaning: boundary first.
- **Web UI framework** — Phoenix/LiveView is the obvious fit given the Elixir server; confirm
  when that work starts.
- **Oban queue/worker design** — which recurring jobs (maintain sweeps, drain, warmth reaping,
  digest) become Oban workers vs staying in-process GenServers.
- **Fresh-seed budget** — how much of `Board.brief` a cold-spawn injects, and whether the brief
  needs a "since you were last here" delta rather than the full standing brief.
