# funes

**Read `docs/spec.md` before writing anything.** It is the specification this repository exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What to build, in order

The build order is the aleph doc's **re-laid §9** (`../../docs/plans/2026-08-14-aleph-cockpit-and-elixir-spine.md`),
which supersedes `docs/spec.md` §9's ordering: the thread/channel is the spine and moves up, so it is
db+doctor → thread+message → agent → the dossier → the board → collectors. Step one is still the database
plus `funes doctor`: **nothing ships that cannot be repaired at 2am** — schema, migrations,
`integrity_check`, JSONL export. Do not skip ahead to a later step because it is more interesting.
**Steps 1–3 are built and green in Elixir:**

- **Step 1** — Ecto over `ecto_sqlite3`, the `collection` migration, `Funes.Doctor` (integrity_check,
  tables, pending migrations, JSONL export), and `mix funes.doctor`. The §4 write contract is re-verified
  on `exqlite`: WAL and foreign keys via PRAGMA, and a **bounded busy_timeout proven by a contention test**
  (exqlite sets it through a NIF, not `PRAGMA busy_timeout`, so a held-lock timing test is the only honest
  probe).
- **Step 2** — `thread` + `message` (`Funes.Channel`): the atom of work and the channel/§4 capture path,
  with `delivered` a separate column from `read` and a sender who cannot fake delivery (§5b.3).
- **Step 3** — `agent` + `session` and staffing (`Funes.Staff`): the durable named identity and its
  ephemeral instance (aleph §3), a thread's `agent_id`, and the opaque `workspace_ref` the arbiter jumps
  into. This is the recipient model step 2 deferred its PubSub wake to await.
- **Step 4** — the dossier: `fact`/`event`/`issue` scoped to threads (`Funes.Dossier`) →
  `LEARNINGS`/`SHIPPED`/`BLOCKERS`. `fact` is the ledger's successor with `provenance` (stated | derived,
  the DB CHECKs it), a separate reproducibility axis `check_cmd`, and explicit `supersedes`; `event` is
  append-only with a closed `kind` that includes the `work_landed` outcome; `issue` is a local,
  ticket-shaped finding read capped-and-counted by `open_issues_for_thread` (§5's acceptance test).

- **The switchboard** (`Funes.Switchboard` + `Funes.Bus` + `Switchboard.Server`, `Funes.Arbiter`) — the
  liveness layer step 2 deferred. Delivery WAKES the recipient (§5b.2): a posted message is broadcast over
  `Phoenix.PubSub` and the switchboard pokes the live sessions on that thread through the **arbiter, a
  capability not a product** (Herdr | tmux, §8) that defaults to `Inert`. §10 holds — the message is a
  durable row before any wake, and `drain/0` re-delivers on restart, so killing the BEAM loses nothing.
  Two guard-rails: the wake is **coalesced** (a backlog is one nudge, not N) and **must be presence-gated**
  before a real poking backend ships — never wake a clocked-out or **cold** session (idle past the ~1h
  prompt-cache warmth window), which is the "resumed a thread and burned my allotment" footgun (aleph §3b).

Change the build-order status line above as each step lands — do not leave it asserting a step that is
already built (the trap the step-2 handoff caught here). Next is **step 5, the aleph board** — the
Drafter TUI rendering all of the above, ranked and cut; the dossier tables feed it directly. Deferred
still: **presence/warmth** (the wake's governor, aleph §3b — required before a real arbiter), the `Sense`
collectors, and cross-thread **mentions**. SQLite is still the truth — a real db reads back under `sqlite3`.

Version one ran on the *work* machine and is **not on this clean-room box** (§8c). It is **evidence, not
a source**: it exists to show what a failure looked like, never to copy a shape. Nothing here needs to be
backwards compatible with it.

## The rules most likely to be broken by accident

- **When two things can answer the same question, delete one.** Three defects in one day were "two
  sources of truth where the untested one was in the live path".
- **Ask the arbiter whose output contains the field you care about.** A test that reads our own files
  proves only that we were consistent. `herdr config check` said `config: ok` about a stale registry
  and `herdr plugin list` printed neither the version nor the actions that had diverged.
- **A field computed at write time is not a fact at read time.** Compute age, staleness and counts in
  the query.
- **A cache that reports an empty world is a lie.** A collector that cannot collect writes nothing and
  says so — and an empty derived scope is never a licence to show everything.
- **Never invent a duration.** A log entry is a stamp, not a clock-in.
- **A measurement that returns nothing must be proven capable of returning something.** A false zero
  from a wrong key reads exactly like a real zero, and one of those got into the spec.
- **Rank and cut every surface.** Complete is not the same as useful; the count of what was set aside
  is the honest way to omit it.
- **No provider, model or vendor is part of the design.** They are configuration. A role states a
  capability requirement — "not the weights that wrote this", "long context", "cheap per turn" — and the
  mapping to an endpoint is local. Local models are first-class, and anything that assumes a frontier
  model must degrade honestly rather than break. The same goes for credentials: how this machine
  authenticates is local configuration and no code here may know which mechanism it is.
- **In production, Andrew presses Enter.** Prefill the exact reviewed text in a visible pane and stop.
  Typing is only inert where `herdr pane process-info` proves a shell is in the foreground.

## The dev loop

Drive everything through the shared mise tasks (`mise tasks` lists them) — the human and any agent use
the same commands, which is the one control loop §3 asks for:

- `mise run funes:test` — the ExUnit suite (`mix test`).
- `mise run funes:check` — compile warnings-as-errors + `mix format --check-formatted` (the gate).
- `mise run funes:setup` — deps + create/migrate the repo-local scratch db (run once).
- `mise run funes:doctor` — `mix funes.doctor` against the scratch db, never the real one.
- `mise run check` — check + tests, the green-before-commit gate.

If a command belongs in the loop, it becomes a task in the root `mise.toml`. Do not invent a second way
to run these.

## Verify

Built test-first (RED before GREEN), and a claim that something works is backed by having run it — the
spec exists because "it works" without running it happened repeatedly in version one. `mise run check`
is the gate; `funes doctor` against a real db, read back with `sqlite3`, is the 2am proof.
