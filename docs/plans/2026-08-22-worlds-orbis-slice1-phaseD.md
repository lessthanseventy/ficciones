# Worlds/Orbis Slice 1 — Phase D: The author face (worlds multiply from the UI) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Companion to `2026-08-21-worlds-orbis-slice1-multiplicity.md` (Phase D was an outline there) and
> `2026-08-21-worlds-orbis-slice1-phaseC.md` (Phase C landed the id-keyed, roster-driven cockpit this builds on).
> Design settled in the 2026-08-22 scoping (operator + claude-machine); see **Decisions** below.

**Goal:** Close the Slice-1 **release bar** — a second world, created at runtime from the cockpit, appears as a second Orbis survey row and is enterable with its own roster spawning lazily, touching no aleph/funes code. Two halves: (1) the Orbis survey gets a real per-row **cursor** so a second world is selectable/enterable (today both `Enter` and click hardcode `Space.first_world()`); (2) an **author face** — Orbis' second altitude-mate to the survey — creates/edits/removes funes `world` rows from **nix-owned world templates**, absorbing the Settings modal.

**Architecture:** The funes backend is done (`Funes.Worlds` context + `register/list/edit/remove_world` MCP tools, `modules/funes/lib/funes/worlds.ex`). Phase C's id-keying dissolved the atom-exhaustion (I1) and slug-collision (I2) blockers, so user-named worlds are now safe. Aleph writes funes **in-process** (the `Channel.open_thread`/`Funes.approve_habit` idiom in `cockpit.ex`), and `Aleph.Worlds`' Bus-subscription auto-refreshes the survey on any world write — so create/edit/remove need no manual reload. The config seam holds: **nix owns capabilities** (world templates + coworker archetypes, compiled into `Aleph.Profiles`/a new registry), **funes owns compositions** (the world rows the author face writes).

**Tech Stack:** aleph (`Aleph.Space`/`Panel.Chorus`/`Keymap`/`Cockpit`/`View`/a new author panel + a world-template registry), funes `Funes.Worlds` (in-process, done). Elixir/OTP, termbox2.

---

## Decisions (from the 2026-08-22 scoping — the load-bearing frame)

1. **Author face = Orbis' SECOND FACE, toggled.** Orbis stays one space with two faces at the same altitude: the **survey** (today's `Chorus`, read/enter) and the **author** (edit). A key toggles between them; the author face replaces the survey center with an editable world list. NOT a modal, NOT a separate space — the design doc's "two faces" vision. It **absorbs the Settings modal**: per-coworker model/yolo becomes per-world roster editing.
2. **Create-world = pick a nix WORLD TEMPLATE + `register_world`.** A new **world-template registry** (nix-owned capability, compiled into aleph — mirrors `Aleph.Profiles.@archetypes` but for whole worlds: `type`, default `paths`, a starter `roster` of archetype+name, `knobs`). "New world" = choose a template, name it, `Funes.Worlds.register/1` with the template's fields. Templates are capabilities (nix); the created row is a composition (funes). NO cloning of existing funes rows (rejected: couples compositions to each other).
3. **Survey gets a real per-row cursor.** The Orbis survey becomes navigable: `j/k` select a world row, `Enter`/click zoom into **that row's** world id (kills the `first_world` bridge in `keymap.ex` + `chorus.ex`). New cockpit state `survey_cursor :: non_neg_integer()`, clamped to the world count.
4. **In-process funes writes, Bus-refreshed.** Author-face create/edit/remove are keymap effects → new `apply_effect` clauses calling `Funes.Worlds.register/edit/remove` directly, flashing on `{:error, changeset}` (the `Channel.open_thread` idiom, wrapped in rescue/catch). No manual survey reload — `Aleph.Worlds` already subscribes to `:world_*` Bus events.
5. **Delete needs a confirm step (new precedent).** No aleph verb destroys a funes row today (threads only close). `remove_world` gets a two-key confirm (verb, then a confirm key) — the minimal safe pattern; flash "press X to confirm" between.
6. **Field widgets by type (generalize Settings' ring model).** `type`/`scope` = enum ring (Settings' `Tab`/`h/l` cycle). `name`/`paths` entries = the existing single-buffer text machinery (`state.input`), generalized to a focused field. `roster` = an add/remove list of `{archetype (ring), name (text)}` rows. `knobs` = **deferred** (Slice 1 ships type/paths/roster; knobs is a later free-form editor).

### Live prerequisites
- funes redeployed with the `world` entity + tools (done, verified Phase C). `Funes.Worlds.all/0` returns the seeded Tlön.
- Phase C on main: cockpit id-keyed, roster-driven, `Profiles.roster_entry/1` + `claude_code_handles/1` extracted.

---

## Phase D0 — the survey cursor (the release-bar plumbing)

**Invariant:** with one world, behavior is unchanged (cursor at 0 → `first_world`). With two, `Enter`/click on the second row zooms into IT. This is independent of the author face and ships first.

### Task D0.1: `survey_cursor` state + `j/k` move it in Orbis

**Files:**
- Modify: `lib/aleph/cockpit.ex` — add `survey_cursor: 0` to the init-state map; a `move_survey/2` (clamp `0..length(worlds)-1`) reached from the Orbis `move` path.
- Modify: `lib/aleph/keymap.ex` — in the Orbis/command path, `j/k` (and `↑/↓`) over the survey emit a survey-move (today `move/2` moves `focused_id` through threads — split so the survey has its own cursor when Orbis' center is the survey face; thread-list panes keep their cursor). Keep it minimal: a `{:move_survey, dir}` effect (or intent) the cockpit clamps.
- Test: `test/aleph/cockpit_test.exs` — `move_survey` clamps and wraps-not (stops at ends); `test/aleph/keymap_test.exs` — Orbis `j`/`k` emit the survey move.

**Step 1 — failing test:** driving `move_survey(state, +1)` with 2 worlds bumps `survey_cursor` 0→1 and clamps at 1 (no wrap past the last). **Step 2-4:** implement. **Step 5 — commit:** `aleph: Orbis survey gets a per-row cursor (j/k)`.

### Task D0.2: `Enter`/click resolve the cursor → that world's id

**Files:**
- Modify: `lib/aleph/keymap.ex:270` — `command(%{key: :enter}, %{active_key: :orbis})` → emit `{:switch_space, <selected world id>}` from `survey_cursor` (drop `Space.first_world().key`). The cockpit resolves `Enum.at(worlds, survey_cursor).id`.
- Modify: `lib/aleph/panel/chorus.ex:52-62` — `pick/3`/`world_at/2` resolve the clicked row index → `Enum.at(worlds, idx).id` (drop `Space.first_world().key`); the survey data must carry each row's world **id** (thread it from `Aleph.Orbis.worlds` — see D0.3).
- Modify: `lib/aleph/cockpit.ex` — the `{:switch_space, key}` handler already sets `active_key`; ensure it takes an integer id. Resolve the Enter selection from `survey_cursor`.
- Test: `test/aleph/panel/chorus_test.exs` — two worlds, click on row 2 → `{:switch_space, <id2>}`; `test/aleph/keymap_test.exs` — Enter with `survey_cursor: 1` → `{:switch_space, <id2>}`.

**Step 5 — commit:** `aleph: Orbis Enter/click zooms into the selected world's id (kills the first_world bridge)`.

### Task D0.3: survey rows carry their world id + per-world leaf attribution

`Aleph.Orbis.worlds/2` today gives the FIRST world all leaves and zeroes the rest (`orbis.ex:50-62`), and the survey row carries a NAME, not an id — so a click can't resolve its own world. Fix both.

**Files:**
- Modify: `lib/aleph/orbis.ex` — each survey row carries `%{id, name, summary, leaves}`; group the machine leaves by their world (by the leaf's world membership if available, else all under Tlön as today but keyed by id so the row resolves). Minimum bar: every row carries its funes **id**; leaf attribution can stay coarse if per-leaf world membership isn't yet modeled (flag it).
- Modify: `lib/aleph/panel/chorus.ex` — render from `%{id, name, ...}`; `world_at` returns the row's id.
- Test: `test/aleph/orbis_test.exs` / `chorus_test.exs` — rows carry ids; a 2-world survey resolves each row to its own id.

**Step 5 — commit:** `aleph: survey rows carry their funes world id`.

### Phase D0 DoD
- aleph suite + `mise run aleph:check` green.
- `grep -n "first_world" lib/aleph/keymap.ex lib/aleph/panel/chorus.ex` → zero (the bridge is gone).
- **Test-verified multiplicity:** a 2-world survey (seed a 2nd world in the test) → `j/k` selects, `Enter` zooms into the selected row's id.
- **Live-verify (operator):** register a 2nd world via the `register_world` MCP tool (or iex), confirm the survey shows 2 rows and `Enter` on the 2nd enters it with its roster.

---

## Phase D1 — the world-template registry (nix-owned capability)

A compiled registry of world archetypes (like `Aleph.Profiles.@archetypes` for coworkers, but for whole worlds): `type`, default `paths`, a starter `roster` (archetype+name entries), `knobs`. The author face's "new world" picks one.

### Task D1.1: `Aleph.WorldTemplates` (or `Profiles.world_templates`)

**Files:**
- Add: `lib/aleph/world_templates.ex` — `@templates %{code: %{type: "code", paths: ["modules/*"], roster: [%{archetype: :surveyor, name: "surveyor"}, %{archetype: :builder, name: "builder"}], knobs: %{}}, life: %{type: "life", paths: [], roster: [%{archetype: :assistant, name: "assistant"}], knobs: %{}}, blank: %{type: "blank", paths: [], roster: [], knobs: %{}}}`. `templates/0`, `template/1` (raises on unknown), `names/0`. Names/paths are STARTERS the operator edits; archetypes reference the nix `@archetypes` registry by atom.
- Test: `test/aleph/world_templates_test.exs` — the 3 templates exist; `template(:code)` carries a surveyor+builder roster; `template(:blank)` is empty.

**Step 5 — commit:** `aleph: world-template registry (code/life/blank world archetypes)`.

### Task D1.2: `new_world_attrs/2` — a template + a name → `register_world` attrs

**Files:**
- Modify: `lib/aleph/world_templates.ex` — `new_world_attrs(template_key, name) :: %{name, type, paths, roster, scope, knobs}` (scope default `"machine"`), the exact shape `Funes.Worlds.register/1` wants (string-keyed roster maps, matching the seed).
- Test: assert the attrs round-trip through `Funes.Worlds.register/1`'s changeset (valid), and the roster shape matches the seed (`[%{"archetype"=>"surveyor","name"=>"surveyor"}, ...]`).

**Step 5 — commit:** `aleph: new_world_attrs builds register_world attrs from a template + name`.

---

## Phase D2 — the Orbis author face (survey ↔ author toggle)

### Task D2.1: the toggle + author-face state

**Files:**
- Modify: `lib/aleph/space.ex` — Orbis' surface gains an author face. Simplest: a cockpit-state flag `orbis_face :: :survey | :author` selects which center panel Orbis' surface renders (`Chorus` vs a new `Panel.Author`). (Do NOT add a second space — Decision 1.)
- Modify: `lib/aleph/keymap.ex` — a toggle key in Orbis (recommend a bare letter; `Tab` is space-switch now, so use e.g. **`a`** for author / re-press to return to survey, or a dedicated toggle) → `{:toggle_orbis_face}`. Settle the exact key in review.
- Modify: `lib/aleph/cockpit.ex` — `orbis_face: :survey` init; `apply_effect({:toggle_orbis_face}, state)` flips it; `View`/surface resolution renders `Panel.Author` when `:author`.
- Test: `keymap_test` (toggle emits the effect), `cockpit_test` (flip), `view_test` (author face renders `Panel.Author`, survey renders `Chorus`).

**Step 5 — commit:** `aleph: Orbis toggles between the survey and author faces`.

### Task D2.2: `Panel.Author` — the editable world list (read + navigate)

**Files:**
- Add: `lib/aleph/panel/author.ex` — renders one row per funes world (`Aleph.Worlds.all/0`): name, type, path/roster counts; a cursor row washed `:selected` (reuse the Leaves/Settings selected-wash idiom). Footer hints (`j/k row · n new · e edit · d delete · a survey`).
- Modify: `lib/aleph/view.ex` — `data_for(Panel.Author, r)` = worlds + the author cursor.
- Modify: `lib/aleph/cockpit.ex` — `author_cursor: 0`; `j/k` move it when the author face is active.
- Test: `test/aleph/panel/author_test.exs` — rows render; cursor washes; `keymap_test` j/k move.

**Step 5 — commit:** `aleph: Panel.Author lists funes worlds with a cursor`.

### Task D2.3: create a world (`n` → pick template → name → register)

**Files:**
- Modify: `lib/aleph/keymap.ex` — `n` in the author face opens a create flow: a template ring (`WorldTemplates.names/0`, `h/l` cycles) + a name text-buffer (reuse `state.input`, `kind: :new_world`), `Enter` registers. Mirrors the `n` new-thread composer, extended with a template ring.
- Modify: `lib/aleph/cockpit.ex` — `apply_effect({:register_world, template_key, name}, state)` → `Funes.Worlds.register(WorldTemplates.new_world_attrs(template_key, name))`, flash on `{:error, changeset}` (the `Channel.open_thread` idiom + rescue/catch). Reject a colliding/blank name (funes `UNIQUE(name)` → changeset error → flash).
- Modify: `lib/aleph/panel/author.ex` (or a small create overlay) — render the template ring + name buffer while creating.
- Test: `cockpit_test` — `{:register_world, :code, "Ficciones2"}` inserts a world (against a test Repo) and the survey/author list grows; a duplicate name flashes an error, no insert.

**Step 5 — commit:** `aleph: create a world from a template in the author face`.

### Task D2.4: edit a world's fields (type/scope ring · paths · roster)

**Files:**
- Modify: `lib/aleph/panel/author.ex` — an edit sub-view for the cursor world: `type`/`scope` enum rings, `paths` (add/remove text entries), `roster` (add/remove `{archetype-ring, name-text}` rows). Field focus cycles (`Tab`), edits via the rings + the text buffer (Decision 6).
- Modify: `lib/aleph/keymap.ex` — `e` enters edit; field-nav + apply keys (model on the Settings modal's `j/k`/`Tab`/`Enter`).
- Modify: `lib/aleph/cockpit.ex` — `apply_effect({:edit_world, id, attrs}, state)` → `Funes.Worlds.edit(world, attrs)`, flash on error. (Name is immutable per the funes `edit_changeset` — surface that.)
- Test: `cockpit_test` — `{:edit_world, id, %{type: "life"}}` updates the row; `author_test` — the edit sub-view renders the rings/lists.

**Step 5 — commit:** `aleph: edit a world's type/paths/roster in the author face`.

### Task D2.5: delete a world (two-key confirm)

**Files:**
- Modify: `lib/aleph/keymap.ex` — `d` on the cursor world arms a confirm (flash "press d again to delete <name>"); a second `d` (or `y`) → `{:remove_world, id}`; any other key cancels. New state `pending_delete :: id | nil`.
- Modify: `lib/aleph/cockpit.ex` — `apply_effect({:remove_world, id}, state)` → `Funes.Worlds.remove(world)`, flash on error; guard against deleting the LAST/active world (or resolve the active key to Orbis if the active world is removed — carry-forward from the Phase C plan's Phase-D note).
- Test: `cockpit_test` — arm→confirm removes; a single `d` doesn't; deleting the active world resolves `active_key` to `:orbis`.

**Step 5 — commit:** `aleph: delete a world from the author face (two-key confirm)`.

### Phase D2 DoD
- aleph + funes suites + `mise run aleph:check` green.
- The Settings-modal per-coworker editing is reachable via the author face's roster editor (absorbed) — or the `,` modal is explicitly kept as a shortcut and noted.
- **Live-verify (operator, the RELEASE BAR):** in Orbis, toggle to the author face, create a 2nd world from a template, name it; toggle back to the survey → it's a 2nd row; `Enter` it → its roster spawns lazily (a fresh `w<id>` session on `aleph-world-<id>`). Edit its type/roster; delete it. **No aleph/funes code touched — the dogfood is "just another world."**

---

## Definition of done (Phase D overall)
- D0–D2 green; aleph + funes suites + `mise run aleph:check` green; boundary intact.
- The Slice-1 release bar is met: a runtime-created 2nd world is enterable from Orbis' survey with its own roster, created/edited/deleted from the author face over nix-owned templates + funes-owned rows.
- No `first_world` bridge in the survey; no atom minted from a user-typed world name (Phase C dissolved this).

## Open sub-decisions to settle in review (flagged, not blocking the plan)
- **The author-face toggle key** (D2.1) — `a`? a dedicated toggle? (`Tab` is space-switch since C3.4.)
- **Per-leaf world attribution** (D0.3) — real per-world leaf grouping needs a leaf→world model that may not exist; coarse-but-id-keyed is the Slice-1 floor.
- **`knobs` editing** — deferred; type/paths/roster ship first.
- **Settings-modal fate** — fully absorbed into the author-face roster editor, or kept as a `,` shortcut too?
