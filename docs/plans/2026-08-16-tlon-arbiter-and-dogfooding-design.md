# tlön — the arbiter capstone and the dogfooding environment

Written 2026-08-16, brainstormed to a definition of "done" with the owner. This is the design behind the
arbiter — the switchboard's actuator — and the shape of **tlön**, the environment in which funes starts
hosting its own development.

## tlön — what the name means

*Tlön, Uqbar, Orbis Tertius* (Borges, 1940): scholars find an encyclopedia of an invented planet, and as
they study the fiction it bleeds into reality and overwrites it. **tlön is the dogfood environment** —
building a fictional system, in a repo named *ficciones*, that becomes the real one you work inside. The
proof that funes works is that funes coordinates funes' own next task. `tlön` is to this stack what
`workbench` was to v1: the name of the place the work happens. (Workbench was v1's proper noun and stays
with it; tlön is 2.0's.)

The **first tlön task** is a fable review pass driven *through* funes — a fresh-context reviewer (§5b's
"Carl") on a thread, talking to a pi coworker over the channel, instead of an outside Claude Code session.

## The goal that defines "done"

Not "the full arbiter, live in production." The goal is: **start a thread, get it over to Claude and pi,
and run a real review pass through funes — done enough to start working on itself.** Everything below is
scoped to that.

## Done — five components, in dependency order

The switchboard already decides *who* to wake (`recipients/1`) and calls the arbiter to actuate; the
arbiter defaults to `Inert` (logs, pokes nothing). "Done" turns that into a live channel between two
hand-spawned panes.

1. **Engine-credit presence** (funes, TDD). `recipients/1` warmth-gates on `last_active_at` (the prompt-
   cache window) but not on the *other* half of "clocked out" — a model out of credits or past its
   rate-limit window. §8 forbids the design from naming a vendor, so the signal is a **pluggable module**,
   symmetric with the arbiter: `config :funes, :engine_presence, Mod` with `clocked_out?(agent) ::
   boolean`, defaulting to a never-clocked-out impl (absent config = today's behaviour, degrade honestly).
   `recipients/1` excludes sessions whose engine is clocked out. This is the design's stated prerequisite:
   fold it in **before** an auto-poking backend replaces `Inert`, so a poke never burns the scarce Claude
   bucket on a rate-limited session.

2. **A real tmux poke backend** (funes). `Funes.Arbiter.Tmux` shells `tmux send-keys` — its **own** thin
   adapter, *not* `Aleph.Tmux` (funes must never import up into a sibling module; the boundary is load-
   bearing). Replaces `Inert` via config on the machine that has panes. The channel goes live: a post or
   @mention actually pokes the addressed pane so a turn happens.

3. **Spawn actuation + cockpit UX** (aleph, next slice). `tmux new-session`/`new-window` + env-in-spawn
   (`Funes.MCP.Spawn` already builds the `export FUNES_*` block), surfaced in the cockpit as: a key to
   **create a thread** (title → `Channel.open_thread`) and the **`s` "open a session" verb** to spawn
   Claude/pi onto the focused thread. The `Aleph.Keymap` pure reducer + `Aleph.Tmux` (`capture`/`send_text`
   /`send_key` already exist) are the hooks. This removes the CLI-only friction the owner flagged.

4. **Deferred — the autonomous cold-thread trigger** (§4c.3). When a message targets a thread with no warm
   session, the *switchboard* auto-spawns a fresh pane. The **mechanism** is component 3; wiring it to the
   switchboard's autonomous decision is the last, most machine-touching rung, and the human stands in for
   it by pressing `s` (§2d: "for the first slices the human is the arbiter"). Not needed to dogfood.

## The one architectural decision — where the switchboard lives

There must be **one funes world** during dogfooding. Today there are two: `aleph:run` reads
`.dev/funes.db`; the `funes:claude`/`pi:*` launchers `rpc` into the always-up **service** (the XDG db). A
cockpit showing one world while the agents live in another cannot dogfood.

This is a **deployment topology**, not a design rewrite — both options run the identical arbiter backend
and spawn seam. What differs is which node runs the single switchboard.

- **A — aleph is the hub** (chosen for now). aleph boots funes + MCP + switchboard on one db; the launchers
  target aleph's node. The switchboard runs *in the interactive session*, so the tmux poke is native (same
  env, same socket, `$TMUX` set), the reactive cockpit is live in-node with no clustering, and it is the
  least plumbing to *start*. Cost: not always-up — quitting aleph stops live delivery (durability holds; db
  is truth, `drain/0` re-delivers on restart).
- **B — the service is the hub** (convergence target). The always-up service holds the switchboard/db/MCP;
  aleph attaches. This is the full §10 always-up vision and the "many UIs over one funes" end-state, and
  the launchers already point here. Cost: aleph must **cluster** (distributed Erlang) for live PubSub, and
  the poke fires from the systemd `--user` service whose env isn't the shell's — *likely* fine (default
  tmux socket is uid-scoped, `pane_ref` is a global `%N` id) but the one real "poked but nothing happened"
  risk.

**Decision: A now, B later.** A gets dogfooding started with the poke working natively and throws away
nothing — the arbiter backend is identical under B, so moving the switchboard into the service is a
config/supervision change, not a rewrite. The move to B is gated on a cheap empirical spike: from
`funes:console`, `tmux send-keys -t %<pane> Enter` — if the service can poke an interactive pane, B is
safe to adopt.

## The safety model — poking an agent is not typing into a production console

§8's hard boundary — "in production the human presses Enter; refuse newline/tab/control bytes; fail
closed" — governs a **production console or remote write**, where a keystroke has an irreversible
side effect. **Waking an agent's pane is a different actuation**: causing a turn is the entire point, so
the poke *sends* Enter deliberately. The arbiter therefore **sanitizes** rather than fails closed — a
message body with embedded newlines is collapsed to one clean line and control bytes stripped before
`send-keys -l` + `Enter`, so the nudge fires without a stray newline submitting mid-text. The fail-closed
production path is a separate, unbuilt actuation and does not gate the agent poke.

## Verification

Presence and the arbiter's decision logic are pure and TDD'd headlessly (`Arbiter.Test` already captures
wakes; the tmux backend's argv builder + sanitizer are pure functions with their own tests). The live
send-keys is the owner's eye-test — a claim it pokes is backed by a pane that moved, run in ghostty.
`mise run check` is the green gate for components 1–2.
