# Reshape Slice A: Workspace Integrity + Seed-on-First-Boot

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Every thread belongs to a real workspace, the default workspace creates itself at boot, and the hardcoded Tlön fallback + flake seed die.

**Architecture:** A new `Funes.Bootstrap` runs at app start (after Repo): seed a default world if the table is empty, then repair threads whose `world_id` is NULL or dangling. `Worlds.remove/1` stops orphaning threads. Aleph's `world_spaces([])` returns `[]` honestly — funes-down renders an empty state, not a fake world.

**Tech Stack:** Elixir/Ecto (SQLite), funes + aleph modules, nix flake service unit.

**Context:** Design in `docs/plans/2026-08-27-clarity-rename-slack-shape-design.md`. Observed drift: live thread with `world_id=5`, world table has only id 1 — `remove_world` orphans threads; nothing backfills. `foreign_keys: :on` is already set (config.exs:9) but only guards *insert-time* refs.

---

### Task 1: `Funes.Bootstrap` (seed-if-empty + repair)

**Files:** Create `modules/funes/lib/funes/bootstrap.ex`, `modules/funes/test/funes/bootstrap_test.exs`

Tests: (1) empty world table → `ensure/0` creates the default workspace ("ficciones", code/machine, `modules/*`, tertius+hronir roster) and returns it; (2) existing world(s) → no new row, oldest world returned, name untouched (a live "Tlön" row survives); (3) thread with NULL `world_id` → repaired to default; (4) thread with dangling `world_id` → repaired; (5) thread with valid non-default `world_id` → untouched; (6) idempotent (run twice, same state).

Implementation: `ensure/0` = `default_world() || seed_default()`, then `repair/1` (one `update_all` where `world_id` is nil or not in `subquery(select w.id)`). `ensure_safe/0` wraps in rescue/catch → `:skipped` (schema may predate migration at boot). Commit.

### Task 2: Wire into boot; delete the flake seed

**Files:** Modify `modules/funes/lib/funes/application.ex` (add `maybe(:bootstrap, true, {Task, &Funes.Bootstrap.ensure_safe/0})` after `start_repo`), `modules/funes/config/config.exs` (test env: `bootstrap: false` — follow how `start_repo` is disabled under test), `modules/funes/lib/funes/release.ex` (delete `seed_world/do_seed_world/legacy_roster?/normalize_roster`; keep migrate/rollback), `flake.nix` (drop the `seed_world()` ExecStartPre line), plus any release/seed tests. Aleph side: `mise.toml` aleph launch lines if they call seed. Run funes suite. Commit.

### Task 3: `Worlds.remove/1` reassigns threads

**Files:** Modify `modules/funes/lib/funes/worlds.ex`, test in `modules/funes/test/funes/worlds_test.exs` (or create).

Tests: removing a world moves its threads to the oldest remaining world; removing the LAST world is refused (`{:error, :last_world}`). Transaction: reassign then delete, announce as today. Check `mcp/tool.ex` `remove_world` handler tolerates the new error tuple. Commit.

### Task 4: `open_thread` gets a workspace, always

**Files:** Modify `modules/funes/lib/funes/channel.ex` (`open_thread`: when attrs carry no `world_id`, put the default world's id), `modules/funes/lib/funes/thread.ex` (open_changeset casts `world_id` if it doesn't already). Tests: opened thread lands in the default workspace; explicit `world_id` respected; dangling explicit id refused by FK (raises — §10 single-source rule, document in test). Same default for `workline_changeset` path via `Workline.open`. Commit.

### Task 5: Aleph — kill the fallback, render empty honestly

**Files:** Modify `modules/aleph/lib/aleph/space.ex` (`world_spaces([]) → []`, delete `tlon_space/0`), `modules/aleph/lib/aleph/orbis.ex` (delete `@fallback_world`; `worlds(rows, []) → []`), sweep `Space.first_world` / `active_world_id` / cockpit.ex:743-750, 2563 nil paths, `modules/aleph/test/aleph/space_test.exs` + orbis/cockpit tests. Empty state: funes-down → picker is `[Orbis]` only; no fake World. Run aleph suite. Commit.

### Task 6: Gates

`mise run check` (all modules) + `mise run flake:check` (flake.nix changed). Fix fallout. Commit any residue; done = both green.
