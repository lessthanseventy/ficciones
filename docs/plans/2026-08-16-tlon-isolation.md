# Tlön isolation — the machine thread is not a project thread

**Date:** 2026-08-16 · **Status:** implemented alongside the tmux-style input flip.

**Problem.** The Tlön machine coworker (`2026-08-16-tlon-machine-coworker.md`) is a funes citizen
on a persistent "machine" thread so its work is remembered. But that thread is a `Funes.Thread` like
any other, so it shows up in the **Comms chorus** and the **Sessions thread list** alongside real
project threads — cluttering the project surfaces with a meta thread. Worse, `Spawn.env("Tlön", …)`
opens a **new** machine thread on every aleph boot (the v1.1 "known limitation"), so they accumulate.

**Decision.** Give `thread` a closed-set `scope` discriminator: `'project'` (default) or `'machine'`,
guarded by a database CHECK (the `state` / `event.kind` precedent — a closed set lives in the DB,
widening it is a migration, which is the point). The project surfaces (`Channel.chorus/0`,
`Channel.open_threads/0`) filter to `scope = 'project'`, so the machine thread is invisible there
but remains a real, queryable thread (its facts/issues/checks survive; the Tlön space reaches it by
id). The machine coworker becomes **find-or-create**: on first Tlön entry, reuse the latest open
`scope = 'machine'` thread if one exists, else open one — no more per-boot accumulation.

This respects funes' spec discipline (§4): a real use appeared (the machine coworker cluttering
project views — the spec's bar for adding a discriminator), the set is closed and CHECK-guarded, and
the spec is amended in the same commit as the code that proves it. `scope` (not `kind`) is the name:
it names *where the thread belongs* (project surface vs the meta/machine surface), not *what kind of
object it is* — `kind` stays reserved for `fact` / `event`.

**Spec amendment** — `docs/spec.md` §5b: `thread.scope` is a closed `('project' | 'machine')` set,
CHECK-guarded, default `'project'`; the project surfaces read `scope = 'project'` only.

## What changed

- **funes migration** `20260816150000_thread_scope.exs` — `ALTER TABLE thread ADD COLUMN scope TEXT
  NOT NULL DEFAULT 'project' CHECK (scope IN ('project', 'machine'))`.
- **`Funes.Thread`** — `scope` field; `open_changeset` casts it.
- **`Funes.Channel`** — `open_thread/1` accepts `scope`; `open_threads/0` and `chorus/0` filter to
  `scope = 'project'`; new `machine_thread/0` (latest open `scope = 'machine'` thread, or nil) for
  find-or-create.
- **`Funes.MCP.Spawn`** — `env/3` threads `scope` through to `open_thread`.
- **`Aleph.Cockpit`** — `spawn_machine_coworker/0` is find-or-create: `Channel.machine_thread/0`
  → `Spawn.join/2` on the existing thread, else `Spawn.env("Tlön", …, scope: "machine")`.

## What this does NOT change

- The roster (`Staff.roster`) still lists `pi-machine` as live — that's *presence*, not a project
  thread, and the user wants isolation from the project surfaces, not invisibility of the coworker.
- The machine thread's facts/issues/checks are unaffected; it's still a first-class funes thread,
  just filtered out of the two project views.
- `n` (new thread) still creates `scope = 'project'` threads only — you can't accidentally create a
  machine thread from the TUI; only the Tlön find-or-create path does.