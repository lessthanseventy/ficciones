# One brain — the cockpit as a client of the always-up server (WS3 plan)

Design: `2026-09-01-tlon-architecture-and-coworker-lifecycle-design.md` §4. This is the "own
plan" it asked for. Surveyed 2026-09-08 against the code, not the docs.

## What is actually coupled (survey 2026-09-08)

- **~25 facade functions.** Every console → server call goes through `Server.*` public
  functions (Board.brief/recent_activity/sidebar, workline_statuses, staffed_machine_threads,
  open/approve_workline, thread_lead, worktree_for_thread, approve/reject_habit, delete_thread,
  latest_operator_message, recall_coverage, pinned, pending_habits, workspace_thread_ids,
  repo_for_workspace, Tickets.file/in_workspace/update/promote, Notes.write/for_scope,
  Workspaces.all, Presence.Thinking.thinking_all, Channel.operator?, Doctor.pending,
  MCP.Spawn.join). No `Server.Repo` in production console code; only tests touch it.
- **Live state = `Server.Bus`** (Phoenix.PubSub `Server.PubSub`, pg adapter): sessions, threads,
  presence, activity, habits, workspaces, per-thread topics. Cockpit + `Console.Workspaces`
  subscribe.
- **Two callbacks run the other way.** `config :server, :crew, Console.Crew` and
  `:arbiter, Console.Arbiter`: the server's spawn_crew/kill_crew MCP tools and the switchboard's
  cold-rotation call INTO the console, which shells out to tmux via `Console.Sessions`.
- **Boot.** `{:server, path: "../server"}` is a sibling OTP app; the server's own
  `application.ex` already gates Repo/Bootstrap/Switchboard/MCP behind `start_*` flags and
  always starts `Server.PubSub`. The console's config flips them on and points at `.dev/tlon.db`
  :4041. `tlon.service` (flake.nix) runs the release as `funes@127.0.0.1` with the
  release-generated `releases/COOKIE`; `bin/server rpc/remote` already use distribution.
- **Tests.** 71 console test files; 14 touch the DB through `Server.*` or `Repo` (test.exs sets
  every `start_*` false and the DB tests bring what they need).

## Target

One server node (`funes@127.0.0.1`, the systemd service, `wb.db`, :4040) owns Repo, MCP, the
switchboard, later web UI + Oban. The cockpit is `console@127.0.0.1`, connected over
distribution, and reaches the server only through one module. `.dev/tlon.db` is for tests and
for hacking on the server itself.

## Shape

```
Console.Backend  (behaviour: one callback per facade function above)
├── Console.Backend.Local   — calls Server.* in-process   (test env; server hacking)
└── Console.Backend.Remote  — :erpc.call(server_node, Server.X, f, args) with a timeout,
                              node monitor + reconnect, {:error, :server_down} when gone
Console.Backend.call/3       — the one entry point every call site uses; impl from config
```

- **PubSub is free.** `Server.PubSub` (pg) already starts on every node that has the `:server`
  app, and pg groups span connected nodes: a broadcast on the server reaches a subscriber on the
  console node with zero code. The console keeps `{:server, path: "../server"}` for the struct
  definitions, `Server.Bus` topic helpers and pure helpers (`Channel.operator?`), with
  `start_repo/bootstrap/start_switchboard/start_mcp` all false outside test.
- **Ecto structs cross the wire as terms.** `%Server.Ticket{}` etc. are plain maps on the wire;
  the console has the struct modules compiled, so pattern matches keep working. `NotLoaded`
  associations travel as-is. No PIDs/funs/streams cross the boundary (survey: none do today).
- **Cookie.** The release's generated `releases/COOKIE` lives in the nix store; the console must
  present the same one. `tlon.service` gets `RELEASE_COOKIE` from a 0600 file
  `~/.local/share/tlon/cookie` (home-manager activation writes it once if absent); the console
  reads the same file. `bin/server remote/rpc` keep working (RELEASE_COOKIE wins over the file).
- **Callbacks invert.** `Console.Crew`/`Console.Arbiter` become server-side modules that find
  the connected console node (`:global` name `Console.Sessions`) and `:erpc` into it; with no
  console connected they return `{:error, :no_cockpit}` and the switchboard logs it. The
  coworker spawner itself moving into the server (so rotation happens with the cockpit closed)
  is phase 5 — it needs `Console.Sessions`' tmux lifecycle to move, which is the web-UI era.

## Phases (each shippable, gates green, small commits)

**0. Node plumbing.** Cookie file + `RELEASE_COOKIE` in tlon.service; console starts distributed
(`mix console.run` → `--name console@127.0.0.1`, cookie from the file); `Node.connect/1`
smoke via `server:*` mise task. Nothing else changes. *Verify:* `bin/server remote` still works;
`Node.ping(:"funes@127.0.0.1")` from a console iex = `:pong`.

**1. The boundary, locally.** `Console.Backend` behaviour + `Local` impl; every one of the ~25
call sites routed through `Backend.call`. Pure refactor, no behaviour change, whole console
suite green (the 14 DB tests unchanged: test env = Local). *Verify:* `mise console:check`, and
`grep -rn "Server\." lib/` shows only structs/Bus/pure helpers.

**2. Remote impl.** `:erpc` with 5 s timeout, `Node.monitor`, reconnect every 2 s while down,
a cockpit "server down" banner + Doctor line. `Server.PubSub` cross-node verified by a test that
starts a `:peer` node (OTP 28) running the server app on a temp DB and asserts a Bus message
arrives. Config: `config :console, :backend, Console.Backend.Remote` in dev/prod,
`TLON_NODE` env (default `funes@127.0.0.1`).

**3. Callbacks.** `Server.Crew.Remote`/`Server.Arbiter.Remote` in the server (erpc to the
cockpit node via `:global`); server config points at them; `Console.Crew`/`Console.Arbiter`
register globally. Cold-rotation test grows a "no cockpit connected" case.

**4. Flip + retire.** `console:run` no longer migrates or exports `TLON_DB`; it connects to the
service. Console dev/prod config: all `start_*` false, no `Server.Repo` config, `mcp_port` gone.
`console:setup/seed` retarget to `server:*`. `.dev/tlon.db` stays for `server:dev`
(`iex --name funes@127.0.0.1 -S mix` in modules/server against the scratch DB — the way to
hack on the server with a live cockpit without touching the service). Runbook + README updated.
*Verify:* the daily cockpit shows the service's threads (CREW no longer `0/6`), post → reply
live; closing the cockpit leaves the service, coworkers and MCP up.

**5. (later, with the web UI)** `Console.Sessions`' harness lifecycle moves server-side so
rotation and spawn_crew work with no cockpit; Postgres when Oban arrives.

## Risks / notes

- `:erpc` timeouts on a busy server (the maintain sweep) must not freeze the TUI: every
  `Backend.call` is wrapped by the existing `Console.Safe`, returning the last good value.
- Big `Board.brief` payloads over distribution are fine on loopback; no streaming needed.
- Two nodes on one SQLite file is still forbidden — `server:dev` and the service must never
  share `TLON_DB` (the mise task asserts the path differs from the service's).
- Console tests keep `Local`; the peer-node test is the only one needing distribution and is
  tagged `:distributed` so `console:check` can run it separately.
