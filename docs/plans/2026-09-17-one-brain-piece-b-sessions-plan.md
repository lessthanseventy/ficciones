# One brain, piece B — sessions to the server (plan, surveyed 2026-09-17)

Umbrella: `2026-09-08-tlon-one-brain-umbrella.md` (B before D; A is built). This is the
detailed plan the umbrella's cadence asks for, written from the code as it is tonight, so the
build can start cold. Master plan piece G.

## What is actually there (survey)

- **Coworkers already run in tmux, per workspace.** `Console.Tmux`: a PRIVATE tmux server per
  workspace (`-L console-workspace-<ws>`), one session `w<ws>`, the lead's window named after
  the lead, leaf threads' windows `t<thread_id>`. `Console.Staffing` (609 lines) materialises
  the roster into that session (`new-session -A`, `new-window`, backoffs against spawn storms,
  the two-phase wake), builds the boot script (TLON_* exports + launcher per archetype), and
  tags windows with thread ids. `Console.Terminal` (285) embeds a tmux attach through
  libghostty; `Console.Sessions` (124) is the registry of those embeds.
- **The server reaches the console through two inverted callbacks** (piece A's bridge):
  `config :server, :crew, Console.Crew` (spawn_role/kill_role behind the `spawn_crew`/
  `kill_crew` MCP tools) and `:arbiter, Console.Arbiter` (wake/spawn behind the switchboard's
  cold rotation). With no console connected they return `{:error, :no_cockpit}` — so **a
  coworker cannot be spawned or woken unless the TUI is open.** That is the bug B fixes.
- **`Server.Session.pane_ref` is opaque** (`%0` for the console's embeds, nil for a
  `server:claude` pane). Nothing outside the console can resolve a session to its window.
- **asterion attaches today** by convention (`tlon.nvim` derives socket/session/window from the
  sidebar's workspace id + lead name) — it works, but it is the console's naming leaking out.

## Target

`Server.Sessions` owns the tmux lifecycle. The console and asterion are two clients that
*attach*; the switchboard spawns and wakes with no client open.

```
Server.Sessions (GenServer, in tlon.service)
  spawn_harness(thread_id, opts)   → new-window in w<ws> on -L console-workspace-<ws>; Staff.start_session with
                                     pane_ref = "console-workspace-<ws>|w<ws>:<window>" (a REAL, resolvable handle)
  wake(session, prompt)            → tmux send-keys to that pane_ref (was Console.Arbiter.wake)
  kill(thread_id | session)        → kill-window
  terminal_target(thread_id)       → {socket, target} for any client that wants to attach
Server.Crew.Local / Server.Arbiter.Local  — the server-side impls; the Remote bridges are deleted
Console.Sessions                    — keeps the libghostty embed, attaches via Sessions.terminal_target
tlon.nvim                           — attaches via GET /api/threads/:id/terminal (the same target)
```

## Status 2026-09-18

Built, with two departures from the steps below: (1) the module is `Server.Staffing` on Oban's cron
(`Server.Jobs.Staff`, each minute), not a GenServer — the tmux session is the state and a minute's
cadence replaced the console's per-frame backoffs; (2) `pane_ref` was left alone — thread → window
resolves by the `@funes_thread` tag (`Server.Arbiter.Tmux.terminal_target/1`), which is what
`/api/threads/:id/terminal` already served. The console's `Console.Staffing` keeps only the centre
embed (an attach), `Console.Arbiter`/`Console.Crew`/`Server.*.Remote`/`Server.CockpitNode` are gone.

## Steps (each a commit, each gated by `mise run check`)

1. **Move `Console.Tmux` → `Server.Tmux`** unchanged (pure naming + `run/3`); console aliases
   it. Tests move with it.
2. **`Server.Sessions`**: lift `Console.Staffing.boot_script/2`, `profile_launcher/3`, the
   `new-session -A`/`new-window` materialisation and the backoffs into a server GenServer
   (started by `tlon.service` — `start_sessions` flag, false in test unless asked). The launcher
   catalogue (which harness per archetype) becomes server config; the console stops owning it.
3. **`pane_ref` becomes the tmux handle** (`socket|session:window`), written by
   `Server.Sessions` at spawn. Sessions from before carry `%0`/nil and are treated as
   unresolvable (a wake on them falls back to `maybe_spawn_absent`).
4. **Arbiter/Crew local impls** in the server; `Console.Arbiter`/`Console.Crew` deleted;
   `config :server, :arbiter/:crew` point at the local impls in the release. The switchboard's
   cold rotation now works with no TUI.
5. **`/api/threads/:id/terminal`** → `{socket, target}` (or 404); tlon.nvim's `attach_argv`
   reads it instead of deriving names. `Console.Terminal` attaches through the same target.
6. **Live check**: kill the console; post to a thread whose lead is cold (`server:post`); the
   lead is spawned into `w<ws>` by the service alone; `tlon.nvim` `t` attaches to it; the
   console, reopened, embeds the same window.

## What B does not do

Postgres (C), the web UI (D), Oban (E) — unchanged in the umbrella. The libghostty embed stays
in the console (display concern). `.dev` stays the scratch node.

## Risks

- `Console.Staffing` is the console's biggest module and the spawn-storm backoffs in it were
  earned live; lift them verbatim, do not "clean up" in the same commit.
- A server-side tmux needs the user session's environment (`DISPLAY`/`WAYLAND_DISPLAY`,
  `XDG_RUNTIME_DIR`) for harnesses that open windows (kitty graphics, `xdg-open`); `tlon.service`
  is a user unit, so they are present — verify in step 6 with a coworker that opens a browser.
