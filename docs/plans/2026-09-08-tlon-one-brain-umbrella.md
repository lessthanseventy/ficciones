# Tlön one brain — the umbrella (client split → sessions → Postgres → web UI → Oban)

The whole arc in one place so each piece is built knowing what comes after it. Detailed,
task-level plans are written per piece, just in time — the roadmap showed that plans written far
ahead go stale. First detailed plan: `2026-09-08-one-brain-client-server-plan.md` (piece A).

## End state

One always-up server node owns everything durable: Postgres (the store), MCP for the coworkers,
the coworker session lifecycle (tmux), Oban for recurring/persistent jobs, and a Phoenix/LiveView
web UI. The TUI cockpit and the web UI are two clients of the same server API and the same
PubSub. Closing either client changes nothing about what is running. `.dev` scratch state is for
tests and for hacking on the server.

```
                ┌──────────────── server node (systemd, always up) ────────────────┐
                │  Server.* contexts (the API)   Server.Bus (PubSub, pg)           │
                │  Postgres ── Ecto              Oban (sweeps, drain, reaping)     │
                │  MCP (Bandit :4040)            Server.Sessions (tmux lifecycle)  │
                │  Phoenix LiveView (Bandit)                                       │
                └──────┬──────────────────────┬────────────────────────┬───────────┘
        :erpc + pg  ───┘                      │ http                   │ tmux attach
   ┌───────────────┐                 ┌────────────────┐        ┌────────────────┐
   │ TUI cockpit   │                 │ browser        │        │ coworkers      │
   │ (console node)│                 │ (LiveView)     │        │ (pi / claude)  │
   └───────────────┘                 └────────────────┘        └────────────────┘
```

## Sequence and why this order

| # | Piece | Unblocks | Size (surveyed 2026-09-08) |
|---|-------|----------|-----------------------------|
| A | **Client split** — `Console.Backend` Local/Remote, cookie plumbing, callbacks inverted, `.dev` retired from daily use | the daily `0/6` (cockpit on the unseeded scratch DB); everything below needs one owner of the store | ~25 call sites, 14 DB tests, 2 callbacks. Detailed plan exists. |
| B | **Sessions to the server** — `Console.Sessions`' tmux lifecycle (spawn_harness, terminal, kill) becomes `Server.Sessions`; the cockpit attaches to windows the server made | cold rotation and `spawn_crew` with no cockpit open; the web UI can start coworkers | sessions.ex is 100 lines of tmux shell-outs; the libghostty attach stays in the console |
| C | **Postgres** — ecto_sqlite3 → postgrex, migrations re-checked, one-shot `wb.db` import | Oban native engine; two nodes on one store (server:dev beside the service); the web UI's concurrency | 37 migrations, SQL is portable (only `lower()` fragments), 224 KB of data; postgres 18 already runs here and is declared for NixOS |
| D | **Web UI** — Phoenix + LiveView in the server app, on the Bandit already serving MCP (second listener or a router split), the same contexts + Bus the TUI uses | a second client; proves the API boundary from A is real | Phoenix scaffolding + one LiveView per cockpit panel worth having; theme from the palette generators |
| E | **Oban** — maintain sweeps, drain, warmth reaping, digests as workers; cron for the recurring ones | reliability + visibility of background work; the "value feedback loop" telemetry has a home | one queue per class; the existing GenServer loops become workers one at a time |

A before everything: it is the only piece that fixes something broken today, and it defines the
API surface (the `Server.*` contexts) that B–E all build on.
B before D: the web UI wants to start coworkers; that must not depend on a TUI being open.
C before D/E: Oban is Postgres-native and LiveView means concurrent writers; doing C on a small
DB with one client is the cheap moment.

## Decisions each piece imposes on the others (settle now, so A does not paint us in)

1. **The API is the `Server.*` context functions, nothing else.** A's `Console.Backend`
   callbacks are exactly those functions; D's LiveViews call the same functions in-process.
   No console-only server endpoints. If the cockpit needs a new read, it becomes a context
   function first.
2. **Events are `Server.Bus` topics, nothing else.** A relies on pg PubSub across nodes; D
   subscribes to the same topics in-process. New live state = a new Bus topic.
3. **Struct payloads stay Ecto schemas** (they travel as terms over erpc). C changes column
   types, not the structs' shape; A's boundary is unaffected by C.
4. **Sessions become a server context in B** (`Server.Sessions`), with the same
   `spawn_harness/terminal/kill` verbs. A's inverted callbacks (`Server.Crew.Remote` →
   cockpit) are a bridge that B deletes; keep them thin.
5. **One Bandit, one port family.** MCP stays loopback :4040. The web UI is a second loopback
   listener (:4042) in D, reachable remotely only over tailscale — no auth story until it is
   needed; Tailscale identity headers are the likely first one.
6. **Node identity.** `funes@127.0.0.1` stays the server node name (release env already sets
   it); the cookie lives in `~/.local/share/tlon/cookie`, home-manager writes it once; every
   client (cockpit, `bin/server remote`, a future dev tool) reads that file.
7. **Config is the flake's.** `tlon.service` env (TLON_*) is the single place runtime knobs
   live; Postgres connection and Oban queues join it in C/E. `mise server:*` tasks operate the
   service; `server:dev` is the scratch-node escape hatch.

## What stays out

- The TUI's terminal embedding (libghostty) stays in the console: it is a display concern.
- Multi-user / auth: not until someone other than Andrew reaches the web UI.
- Moving the astal shell's Tlön cards onto the web API: they read the MCP/HTTP surface today;
  revisit after D if LiveView makes them redundant.

## Cadence

Each piece: survey the code first (the console keeps running ahead of its docs), write the
detailed plan, build in small commits with gates green, verify live in the cockpit, update this
table's status. Statuses: **A** BUILT 2026-09-08 (phases 0–4 on main; eye-pass + a cockpit banner left) · B–E not started.
