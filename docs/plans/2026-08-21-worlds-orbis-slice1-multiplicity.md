# Worlds/Orbis Slice 1 — Multiplicity — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make worlds multiply. A first-class funes `world` entity (compositions = data) + MCP tools + flake-seeded Tlön; aleph reads worlds from funes instead of hardcoding; zoom-into-world generalizes the hardcoded `tlon` session/roster to spawn any world's roster by name; an author face creates a second world at runtime. **Release bar:** a second world row appears in Orbis' survey, spawned from the author face, touching no aleph/funes code.

**Architecture:** funes owns compositions (the `world` table, referencing capabilities by name), nix owns capabilities (the archetype profile templates from layer 1). aleph reads `list_worlds` and drives its picker/survey/spawn from that data. The layer-1 `@seed_roster` shape (`{archetype, name, model?, knobs}`) IS a world's `roster[]`. Built in phases so the scary config-truth + live-spawn-rewire land against the proven Slice-0 skeleton one increment at a time.

**Tech Stack:** funes (Ecto+SQLite, Anubis MCP, `Funes.Release`), aleph (`Aleph.Space`/`Cockpit`/`Profiles`/`Orbis`), the layer-1 archetype registry. Cross-module.

---

## Phasing (each phase is independently shippable + verifiable)

- **Phase A — funes `world` entity + tools + seed.** Pure funes; no aleph change. Ends green with a seeded Tlön row queryable via `list_worlds`.
- **Phase B — aleph reads worlds from funes.** Replace the two Slice-0 hardcodes (`Space.all/0`'s Tlön struct, the literal `"Tlön"` in `Orbis.worlds/1`) with reads of funes worlds. With one seeded world, behaviorally **identical to today** — proves the data path with zero UX change.
- **Phase C — zoom-into-world spawns a world's roster (de-singleton the cockpit).** Generalize `@machine_agent`/`@machine_window`/`@tlon_session`/`@base_coworkers`/the three `ensure_*_coworker` spawners to spawn a world's roster keyed by instance name. The risky part — **re-plan in full detail after Phase B lands** (the cockpit map is in `docs/plans/` session notes; the singletons are enumerated in Deferred below).
- **Phase D — author face creates a second world.** Form over a seeded row (absorbs Settings modal); `register_world` from the UI; the release bar. **Re-plan after Phase C.**

This plan details **Phase A and Phase B in full**. Phases C and D are scoped outlines here and get their own detailed task breakdown once B is green — because C's exact shape depends on B's read-seam and D's on C's spawn API. Do not execute C/D from the outline alone.

---

## Phase A — funes `world` entity + tools + seed

### Task A1: the `world` table migration

**Files:**
- Create: `modules/funes/priv/repo/migrations/<timestamp>_world.exs` (use a real timestamp > the latest existing migration; the plan-runner picks it, since `Date.now` is unavailable to the planner)
- Test: covered by A2/A3 (migration runs in the test DB setup)

**Step 1:** Write the migration mirroring the `fact` table's raw-SQL style (`priv/repo/migrations/20260815110000_fact.exs`). Plain SQL, CHECK-guarded `type` and `scope`:
```elixir
defmodule Funes.Repo.Migrations.World do
  use Ecto.Migration
  def change do
    execute("""
      CREATE TABLE world (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL DEFAULT 'code' CHECK (type IN ('code','life','blank')),
        scope TEXT NOT NULL DEFAULT 'machine' CHECK (scope IN ('project','machine')),
        paths TEXT NOT NULL DEFAULT '[]',      -- JSON array
        roster TEXT NOT NULL DEFAULT '[]',     -- JSON array of {archetype,name,model?,knobs}
        knobs TEXT NOT NULL DEFAULT '{}',      -- JSON object
        created_at TEXT NOT NULL
      )
    """, "DROP TABLE world")
    create unique_index(:world, [:name])
  end
end
```

**Step 2:** `cd modules/funes && mise exec -- mix ecto.migrate` (test env auto-migrates); expect clean.

**Step 3-5:** Commit: `funes: world table migration`.

### Task A2: the `Funes.World` schema + changesets

**Files:**
- Create: `modules/funes/lib/funes/world.ex`
- Test: `modules/funes/test/funes/world_test.exs`

**Step 1 — Failing test:** a valid `register_changeset` inserts; an invalid `type` raises at the DB (per funes convention — schema doesn't re-check CHECK columns); `paths`/`roster`/`knobs` round-trip as JSON.

**Step 3 — Implement** mirroring `lib/funes/fact.ex`: `schema "world"` with `field :name`, `field :type`, `field :scope`, `field :paths, Funes.JsonColumn`, `field :roster, Funes.JsonColumn`, `field :knobs, Funes.JsonColumn`, `field :created_at, :utc_datetime`. `register_changeset/1` casts name/type/scope/paths/roster/knobs, `validate_required([:name])`, `put_change(:created_at, DateTime.utc_now())`. `edit_changeset/2` casts the mutable fields (not name/created_at). (Reuse `Funes.JsonColumn` — the fact schema already uses it.)

**Step 5 — Commit:** `funes: Funes.World schema + changesets`.

### Task A3: the `Funes.Worlds` context

**Files:**
- Create: `modules/funes/lib/funes/worlds.ex`
- Modify: `modules/funes/lib/funes.ex` (add `Funes.Worlds` to `exports:` so aleph can read it directly — Phase B)
- Test: `modules/funes/test/funes/worlds_test.exs`

**Step 1 — Failing test:** `register/1` inserts + announces; `all/0` lists newest-first; `get/1`/`by_name/1` return nil when absent; `edit/2` updates mutable fields; `remove/1` deletes; `register` is idempotent-safe on duplicate name (returns `{:error, changeset}` on the unique index, not a crash).

**Step 3 — Implement** the context pipe (`attrs |> World.register_changeset() |> Repo.insert() |> Bus.announce(:world_registered)`), `all/0 = Repo.all(from w in World, order_by: [desc: w.id])`, `by_name/1`, `edit/2`, `remove/1`. Add `:world_registered`/`:world_edited`/`:world_removed` Bus topics if the Bus enumerates them. Add `Funes.Worlds` to `funes.ex` `exports:`.

**Step 5 — Commit:** `funes: Funes.Worlds context (register/list/edit/remove)`.

### Task A4: the four MCP tools

**Files:**
- Modify: `modules/funes/lib/funes/mcp/server.ex` (4 new `component(...)` lines)
- Modify: `modules/funes/lib/funes/mcp/tool.ex` (4 tool modules)
- Modify: `modules/funes/lib/funes/mcp/brief.ex` (a `world/1` result shaper)
- Test: `modules/funes/test/funes/mcp/world_tools_test.exs`

**Step 1 — Failing test:** each tool's `execute/2` — `register_world` inserts + returns `{"world_id" => id}`; `list_worlds` returns the shaped list; `edit_world`/`remove_world` mutate; changeset errors return `Response.error` with a sentence (via `changeset_error/1`).

**Step 3 — Implement** modeled on `Funes.MCP.Tool.BankFact` (write) and `GetFacts` (read). `register_world` schema: `field :name, :string, required: true`, `field :type, :enum, values: ["code","life","blank"], default: "code"`, `field :paths, {:list, :string}`, `field :roster, ...` (accept a JSON/list of maps), `field :scope, :enum, values: ["project","machine"], default: "machine"`, `field :knobs, :map, default: %{}`. Handlers call `Funes.Worlds`. A world is machine-global, so these tools do NOT read `identity.thread_id` (unlike BankFact) — model on the identity-light shape. Register all four in `server.ex`.

**Step 5 — Commit:** `funes: register/list/edit/remove_world MCP tools`.

### Task A5: seed the Tlön world at bootstrap

**Files:**
- Modify: `modules/funes/lib/funes/release.ex` (add `seed_world/0`, idempotent find-or-create)
- Modify: `../../flake.nix` (the `funes` systemd user service ~L743 — a second `ExecStartPre` calling `bin/funes eval 'Funes.Release.seed_world()'` after migrate)
- Test: `modules/funes/test/funes/release_seed_test.exs`

**Step 1 — Failing test:** `seed_world()` with no Tlön row creates it (`name: "Tlön"`, `type: "code"`, `scope: "machine"`, `paths: ["modules/*"]`, `roster: [%{archetype: "surveyor", name: "tertius"}]`); called twice, it's idempotent (one row).

**Step 3 — Implement** `seed_world/0` mirroring `migrate/0` in `release.ex`: `Funes.Worlds.by_name("Tlön") || Funes.Worlds.register(%{...})`. Add the `ExecStartPre` line to the flake service. (Do NOT fold into a migration — a release entrypoint matches the flake's migrate-before-boot idiom.)

**Step 5 — Commit:** `funes: seed the Tlön world row at bootstrap`.

**Phase A DoD:** `cd modules/funes && mix test` green; `mix precommit` (boundary + warnings-as-errors) green; `list_worlds` returns the seeded Tlön row; `Funes.Worlds` exported. Boundary intact (all `Funes.*` internals, no new outward deps).

---

## Phase B — aleph reads worlds from funes

### Task B1: an `Aleph.Worlds` CACHED read seam (event-driven)

**Why a cache, not a thin read (discovered during execution):** `Space.all/0` is called per-render in hot paths (`view.ex`, cockpit `tlon_layout`, `keymap`). A direct `Funes.Worlds.all/0` there = a funes DB read every render — the same per-frame-gather regression the Orbis survey caught. So the seam must be an event-driven cache.

**Design:** a small `Aleph.Worlds` GenServer that:
- On init, loads `Funes.Worlds.all/0` into state and subscribes to the funes worlds Bus topic (`Funes.Bus.subscribe_worlds/0` — added in Phase A; funes runs in-process in aleph, so this works like the cockpit's existing `Funes.Channel`/`Board` reads).
- On `{:world_registered|world_edited|world_removed, _}` → reloads the cache.
- Exposes `Aleph.Worlds.all/0` reading the cached list (cheap — no DB hit per render). Returns aleph-shaped `%{name, type, paths, roster, scope}` maps.
- Funes-down at init / empty → `[]` (callers apply the hardcoded-Tlön fallback in B2/B3). Guard the load in a try/rescue so a funes hiccup can't crash aleph boot.
- Add it to the aleph supervision tree.

**Files:**
- Create: `modules/aleph/lib/aleph/worlds.ex` (the GenServer + `all/0`)
- Modify: the aleph application supervisor (`lib/aleph/application.ex`) — start `Aleph.Worlds`
- Test: `modules/aleph/test/aleph/worlds_test.exs` — cached read returns worlds; a `:world_registered` Bus message refreshes the cache; funes-down/empty → `[]`. (Drive the GenServer directly; assert it reflects a registered world without a per-call DB read.)

### Task B2: `Space.all/0` derives the World space from funes

**Files:**
- Modify: `modules/aleph/lib/aleph/space.ex` — the picker becomes `[Orbis | world_spaces()]` where `world_spaces()` maps `Aleph.Worlds.all()` to Space structs (surface `[WindowBar, {Terminal, :machine}, Pulse]`, `coworker` from the world's roster lead). With one seeded world this yields exactly today's `[:orbis, :tlon]`. **Fallback:** if funes is down / no worlds, keep the hardcoded Tlön so aleph never boots empty.
- Test: `modules/aleph/test/aleph/space_test.exs` (extend — one seeded world → `[:orbis, :tlon]`; two → `[:orbis, w1, w2]`).

### Task B3: `Orbis.worlds/1` groups by real worlds

**Files:**
- Modify: `modules/aleph/lib/aleph/orbis.ex` — replace the literal `"Tlön"` with the world name(s) from `Aleph.Worlds.all()`, grouping each world's leaves under its row. One world today → identical survey.
- Test: `modules/aleph/test/aleph/orbis_test.exs`.

**Phase B DoD:** `mise run aleph:check` green; with the single seeded Tlön world, the picker/survey/spawn are **behaviorally identical to Slice 0** (verified by the existing Slice-0 tests staying green + the extended world tests); the hardcodes are gone (grep `"Tlön"` in `space.ex`/`orbis.ex` → only via funes data). **Live-verify:** boot, confirm Orbis↔Tlön still works driven by funes data.

---

## Phase C — zoom-into-world spawns a world's roster (OUTLINE — re-plan after B)

The de-singletoning. Today these are hardcoded to one coworker/session (map from the session's cockpit-spawn survey):
- `@machine_agent "tertius-machine"` / `@machine_window "tertius"` / `@claude_agent`/`@claude_window` / `@tlon_session "tlon"` (`cockpit.ex:54-68`) — one name each.
- `@base_coworkers` fixed 2-entry map + the `$TLON_THIRD_AGENT` escape hatch (`mention.ex:25-37`).
- Three hand-written singleton spawners `ensure_machine_coworker`/`ensure_claude_coworker`/`ensure_third_coworker` (`cockpit.ex:1440-1515`).
- `tlon_tmux/1` derives its socket from `Space.fetch(:tlon).coworker` (`cockpit.ex:1784`).

**Direction:** entering world N attaches its own tmux session (keyed by world name) and lazily spawns its `roster[]` — each entry `Profiles.instantiate(entry)` (layer 1) → a window keyed by the instance name; `Aleph.Mention` routes by instance handle (`#{name}-machine`) instead of the fixed map. One `ensure_world_roster(world)` loop replaces the three singletons. Re-plan with exact tasks after Phase B.

---

## Phase D — author face creates a second world (OUTLINE — re-plan after C)

Form over a seeded row (absorbs the Settings modal): edit a world's type/paths/roster/knobs; "new world" = duplicate a template + `register_world`. The release bar: a second world row in Orbis' survey, spawned from the UI, no aleph/funes code touched. Re-plan after Phase C.

---

## Definition of done (Slice 1 overall)

- Phases A-D green; funes `mix test` + `mise run aleph:check` green.
- A second world, created from the author face at runtime (no rebuild, no code), appears as a second Orbis survey row and is enterable with its roster spawning lazily. **That is the release bar — the dogfood becomes "just another world."**
- Boundary law intact; Tlön is now an ordinary funes world row (editable), no longer special-cased in `Space.all/0`.

## Deferred (beyond Slice 1)

- Per-type panel-sets (code vs life vs blank drop dead furniture) — "Later."
- Grouping worlds into orgs/folders — YAGNI until the flat list is crowded.
- Importing external agent templates into the archetype registry.
- The crew/coordination engine (layer 3) — separate strand.
