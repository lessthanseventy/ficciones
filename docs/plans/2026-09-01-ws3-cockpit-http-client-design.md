# WS3 — one always-up server, cockpit as HTTP client (design + phased plan)

**Date:** 2026-09-01
**Status:** designed (transport decided); to be executed over several focused sessions
**Decision (Andrew):** the cockpit talks to the always-up server over **HTTP** — the same seam the
future web UI and Oban dashboard use. One server owns the DB; the cockpit, agents, and the web UI
are all clients. (Chosen over distributed-Erlang `:erpc` because it decouples cleanly and the web
UI needs an HTTP path anyway.)

> Prereq reading: `2026-09-01-tlon-architecture-and-coworker-lifecycle-design.md` (why one brain),
> `2026-09-01-tlon-roadmap.md` (where this sits). **Verify current state before each phase — this
> session repeatedly found things already built.**

## Current state (grounded 2026-09-01)

- The console **embeds** the server (`{:server, path: "../server"}`) and calls **~19 distinct
  `Server.*` modules in-process** (Channel, Board, Dossier, Staff, Tickets, Notes, Workspaces,
  Presence, Bus, Worktree, …). Same BEAM node, one Repo.
- Live updates: the cockpit **subscribes to `Server.Bus`** (in-process PubSub) and re-renders on
  events.
- The server already serves **HTTP via Bandit**: MCP over StreamableHTTP (the `mcp/gateway` →
  anubis) plus a `POST /mint` token endpoint. MCP **tools** (`mcp/tool.ex`) cover the *agent* verbs
  — NOT the cockpit's rich reads.
- Two DBs today: embedded cockpit server on :4041/`.dev/tlon.db`, systemd service on
  :4040/`wb.db`. WS3 collapses these to one always-up server.

## Target architecture

```
                 always-up server (one node, owns the DB)
        ┌──────────────┬───────────────┬──────────────┬──────────┐
        │  JSON API    │  MCP (agents) │  SSE /events │  web UI  │  + Oban
        └──────┬───────┴───────┬───────┴──────┬───────┴────┬─────┘
           cockpit          agents         cockpit       browser
        (HTTP client)      (MCP)         (live stream)  (LiveView)
```

The cockpit stops embedding `:server`. It becomes an HTTP client: **reads** via a batched JSON
snapshot endpoint, **writes** via JSON POSTs, **live updates** via an SSE stream that bridges the
server `Bus`. The `.dev`/:4041 embedded brain is retired; `.dev` DBs become test-only.

## The two hard design points

1. **Latency / per-frame reads.** The cockpit assembles a heavy read map *every render*. An HTTP
   round-trip per frame is unacceptable. So the API is NOT a chatty mirror of the 19 modules —
   it's **one batched `GET /cockpit/snapshot?workspace=…`** returning the whole read map the View
   needs, plus the **SSE `/events`** stream pushing deltas so the cockpit re-renders from a locally
   cached snapshot without re-fetching. (This also naturally serves the web UI.)
2. **The Boundary flip.** Today the `:boundary` compiler enforces "console may only call exported
   `Server.*`." After WS3 the console no longer depends on `:server` at all — it depends on an HTTP
   client + shared response shapes. The shared shapes (structs/JSON contracts) want a small shared
   library (or duplicated typed maps) so both ends agree without a code dependency.

## Phased migration (keep it working the whole way)

Do it **while still embedded first** (call the API over localhost), so each phase is verifiable
before the node split — de-risking the big cutover to the end.

- **Phase A — read API + client (reads through HTTP, still one node).** Build the batched
  `GET /cockpit/snapshot` (+ any focused reads) on the server's Bandit, serializing the same map
  `Console.View` consumes. Add a `Console.Api` client. Route the cockpit's **reads** through it
  behind a flag; assert the View renders identically. No behavior change — pure seam insertion.
- **Phase B — write API.** JSON POSTs for every operator write (post_message, open_thread,
  file_ticket, write_note, forget_fact, delete_thread, edit_workspace, …). Route the cockpit's
  writes through `Console.Api`. Auth: the cockpit mints an **operator-scoped token** (reuse the
  `/mint` infra).
- **Phase C — live updates via SSE.** Add `GET /events` that bridges `Server.Bus` to an SSE stream
  (per-workspace / per-thread topics). Replace the cockpit's in-process `Bus.subscribe_*` with the
  stream + local snapshot cache. Now the cockpit needs nothing in-process from the server.
- **Phase D — split the node.** Drop `{:server, path: …}` from the console; point `Console.Api` at
  the **always-up** server (the systemd service, now the single seeded real DB). Retire the
  embedded :4041/`.dev` brain. `console:run` no longer boots a server. Flip the Boundary rules.
- **Phase E — the payoff (future).** Web UI (Phoenix/LiveView) over the same server + API; Oban for
  persistent/scheduled jobs (maintain sweeps, drain, warmth reaping, digests). **SQLite → Postgres**
  likely lands here (Oban-native + concurrent web clients); the client boundary built in A–D means
  the store swap is behind the server, invisible to the cockpit.

## Risks / open decisions

- **Snapshot shape drift.** The JSON snapshot must stay in lockstep with what `Console.View`
  expects. Mitigate with a shared contract module + a round-trip test (server serializes → cockpit
  deserializes → View renders).
- **SSE vs WebSocket** for `/events` — SSE is simpler (one-way, HTTP), sufficient (the cockpit only
  *reads* the stream; writes go through POSTs). Default SSE; revisit if bidirectional is needed.
- **Auth scope.** The cockpit is a *privileged operator* client (can delete threads, forget facts).
  Its token needs an operator scope distinct from an agent's thread-scoped token.
- **Postgres timing** — build A–D on SQLite; migrate the store in E. Don't block the client boundary
  on the store swap.
- **Always-up ownership** — the systemd service becomes the one server; `console:run` attaches to
  it. Decide dev ergonomics (hot-reload of server code now happens in the service, not the cockpit).

## Sequencing note

Phases A–C are safe, incremental, individually shippable, and reversible (behind a flag), all while
the app keeps working on one node. Phase D is the real cutover. E is the future. Start at A with a
fresh head — it's a from-scratch API surface, not a tweak.
