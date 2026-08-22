# Worlds/Orbis Slice 1 — Phase C: De-singleton the live cockpit — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Companion to `docs/plans/2026-08-21-worlds-orbis-slice1-multiplicity.md` (Phase C was an outline there).
> Design settled in the 2026-08-21 brainstorm (operator + claude-machine); see **Decisions** below.

**Goal:** Take the cockpit off the hardcoded `:tlon` singleton so entering any world spawns *that world's* roster, keyed by funes world id — dissolving the atom-exhaustion / slug-collision / silent-Orbis-fallback risks and splitting the surface into "tab bar = leaders, Leaves panel = leaves."

**Architecture:** Three independently-shippable sub-slices against the proven Phase-B read seam. **C1** flips every aleph-internal key from the `:tlon` atom to the funes world id (pure refactor, one world → behaviorally identical). **C2** replaces the three hardcoded coworker spawners with one `ensure_world_roster(world)` driven by `world.roster[]`, adds a per-archetype `harness` field, and per-world tmux naming. **C3** filters the WindowBar to leader windows and surfaces `t<id>` leaves in a leader-grouped Leaves panel with select-to-attach.

**Tech Stack:** aleph (`Aleph.Cockpit`/`Space`/`Keymap`/`Worlds`/`Profiles`/`Panel.*`), the Layer-1 archetype registry, funes `Funes.Worlds` (in-process). Elixir/OTP, termbox2, tmux.

---

## Decisions (from the brainstorm — the load-bearing frame)

1. **World identity = funes id.** `active_key :: :orbis | non_neg_integer()`. The World struct carries `name` for every human-facing use (tab label, tmux session label, mention handles, logs). Id-keying is the only option where Phase D's **rename** of the active world isn't session-breaking, and it dissolves atom-exhaustion (I1) and slug-collision (I2) at the root. Funes-down fallback Tlön uses sentinel key `0` (real ids ≥ 1).
2. **Roster = the full leader cast.** `world.roster[]` head = the **lead** (the world's Orbis face + default-focused tab), tail = supporting peers. All leaders are **structurally peer tmux windows** — "which one runs `new-session`" is an impl detail, not a role. A third coworker is a third roster entry (the `$TLON_THIRD_AGENT` hatch dies).
3. **Harness per archetype.** Add `harness :: :pi | :claude_code` to each archetype template (`builder → :claude_code`, rest `→ :pi`). `ensure_world_roster` dispatches the launcher per entry, preserving today's live cast (`hronir` stays the real `claude` CLI).
4. **Surface split.** Tab bar (WindowBar) = leaders only; `t<id>` leaves move to the Leaves panel; selecting a leaf **attaches** (center follows). Selecting a leader **floats that leader's leaves to the top** of the Leaves panel. Secondary views hide behind `[`/`]` binds (lazygit-style within-pane flip).
5. **One embedded terminal per world**, spawned lazily on first entry, kept alive (worlds are few; simpler than one re-pointed PTY). Session `w<id>`, server socket `aleph-world-<id>` (both id-derived — rename-proof).
6. **`Space.fetch/1` is explicit** — returns `nil` on a miss (drop the silent-Orbis default); a `world?/1` predicate replaces the ~40 `active_key == :tlon` **mode** guards.

### Weird patterns we shed (evolve past — do NOT parameterize)

| Today | Target |
|---|---|
| pi-center vs claude-window structural asymmetry | leaders are peer windows |
| `uqbar` move-window-to-tab-0 renumber dance | tab order = roster order |
| `$TLON_THIRD_AGENT` env hatch | third coworker = third roster entry |
| `@base_coworkers` fixed 2-entry map | mention routing derived from roster |
| `Space.fetch` silently defaults to Orbis | `nil` on miss / `fetch!/1` raises |
| `String.to_atom` name-slug (`space.ex:131`) | id keys |
| leaves as tabs | leaves in the Leaves panel, attach-to-view |

`harness` (pi vs real-claude) **stays** — a capability difference, not a weird pattern. `char_key/1`'s `String.to_atom` (`cockpit.ex:993`) **stays** — bounded a-z0-9, not a name.

### Live prerequisites (verified 2026-08-21)

- funes redeployed with the `world` entity; `Funes.Worlds.all/0` on the running node returns the seeded Tlön (`id: 1, roster: [{surveyor, "tertius"}]`). ✅ confirmed via `bin/funes rpc`.
- **Before C2:** the seed roster grows to include the builder — either re-seed (`Funes.Release.seed_world` gains the `builder` entry + an idempotent `edit_world` to backfill existing rows) or an operator `edit_world` on row 1. C2 Task C2.6 covers this.

---

## Phase C1 — key everything by world id (pure refactor, zero behavior change)

**Invariant:** with the single seeded Tlön world (`id: 1`), the cockpit is behaviorally identical to Phase B — same tabs, same spawn, same nav. The only change is the internal key: `:tlon` → `1` (or `0` on the funes-down fallback). Verified by the existing Slice-0/Phase-B tests staying green plus new id-keyed assertions. **This is the atomic flip** — the moment `active_key` becomes an integer, every `%{active_key: :tlon}` clause stops matching, so all sites convert together.

### Task C1.1: `Aleph.Worlds` carries the world id

The cache drops `:id` today (`@fields [:name, :type, :paths, :roster, :scope]`) — nothing downstream can key by id until it's surfaced.

**Files:**
- Modify: `lib/aleph/worlds.ex` (the `@fields` module attr, ~L33)
- Test: `test/aleph/worlds_test.exs`

**Step 1 — failing test:** register a world via funes, assert `Aleph.Worlds.all/0` returns a map with `:id` matching the funes row id.
```elixir
test "cached worlds carry the funes id" do
  {:ok, w} = Funes.Worlds.register(%{name: "Test", type: "code"})
  start_supervised!({Aleph.Worlds, name: :worlds_id_test})
  assert [%{id: id, name: "Test"}] = Aleph.Worlds.all(:worlds_id_test)
  assert id == w.id
end
```
**Step 2 — run, expect FAIL** (`:id` absent). `cd modules/aleph && mise exec -- mix test test/aleph/worlds_test.exs`
**Step 3 — implement:** add `:id` to `@fields`. `@fields [:id, :name, :type, :paths, :roster, :scope]`.
**Step 4 — run, expect PASS.**
**Step 5 — commit:** `aleph: Aleph.Worlds cache carries the world id`.

### Task C1.2: `Space` keys worlds by id; drop the slug; explicit `fetch`

**Files:**
- Modify: `lib/aleph/space.ex` (`space_from_world`, `tlon_space`, `slug/1` removal, `fetch/1`, the struct)
- Test: `test/aleph/space_test.exs`

**Step 1 — failing tests:**
```elixir
test "a world space is keyed by its funes id" do
  spaces = Aleph.Space.all([%{id: 7, name: "Tlön", roster: [%{"name" => "tertius"}], type: "code", paths: [], scope: "machine"}])
  assert [%{key: :orbis}, %{key: 7, label: "Tlön", id: 7}] = spaces
end

test "the funes-down fallback Tlön keys as 0" do
  assert [%{key: :orbis}, %{key: 0, label: "Tlön"}] = Aleph.Space.all([])
end

test "fetch returns nil on a missing key (no silent Orbis default)" do
  assert Aleph.Space.fetch(:orbis, [%{id: 1, name: "Tlön", roster: [], type: "code", paths: [], scope: "machine"}]).key == :orbis
  assert Aleph.Space.fetch(999, [%{id: 1, name: "Tlön", roster: [], type: "code", paths: [], scope: "machine"}]) == nil
end

test "world?/1 is the mode predicate" do
  refute Aleph.Space.world?(:orbis)
  assert Aleph.Space.world?(1)
  assert Aleph.Space.world?(0)
end
```
**Step 2 — run, expect FAIL.**
**Step 3 — implement:**
- Add `:id` and `:roster` to the struct: `defstruct [:key, :label, :surface, :id, left: [], right: [], coworker: nil, roster: []]` (roster carried for C2/C3).
- `space_from_world(world)`: `key: world.id, id: world.id, label: world.name, ..., coworker: lead_coworker(world.roster), roster: world.roster`.
- `tlon_space` (fallback): `key: 0, id: 0, ...` — document the sentinel.
- Delete `slug/1` (kills the `String.to_atom` at L131).
- `world?(:orbis)`/`world?(k) when is_integer(k)`.
- `fetch/1` (and a pure `fetch/2` over an explicit list): `Enum.find(spaces, &(&1.key == key))` — **no** default arg; returns `nil` on miss. Keep `all/0`→`all(fetch_worlds())` and add `fetch/2` for tests. Update `next/2`/`prev/2`/`step` to tolerate `nil` (an unknown key → start at Orbis via `|| 0` index, unchanged).
**Step 4 — run, expect PASS** (plus existing space tests green — the one-world case still yields `[:orbis, <id 1>]`).
**Step 5 — commit:** `aleph: Space keys worlds by funes id, drops the name slug`.

### Task C1.3: convert the cockpit's `:tlon` guards to id-keyed

The atomic flip. **Inventory** (from `grep -n active_key lib/aleph/cockpit.ex` + `:tlon`): the render map gates (`cockpit.ex:1049-1072`), `machine_read`, `center_terminal`, `composer_thread_id`, `tlon_layout`, `tlon_detail`, `ensure_probes`, `preview_focused`, the four `ensure_*_coworker`/`ensure_log_window`/`ensure_thread_sessions` guards, `init` (`active_key: List.first(Space.all()).key`). ~42 sites.

**Transformation rules (apply uniformly):**
- `%{active_key: :tlon} = state` clause head → `%{active_key: k} = state when Aleph.Space.world?(k)`. Where the body needs the id, bind `k`.
- `active_key == :tlon` (in `if`/map-gate expressions, L1055-1072) → `Space.world?(state.active_key)`.
- `active_key == :orbis` — unchanged (Orbis stays the `:orbis` atom).
- `safe_terminal(:machine)` / `safe_spawn_harness(:machine, …)` → key the embedded terminal by the **active world id**: `safe_terminal(active_world_key(state))` where `active_world_key(%{active_key: k}) when is_integer(k), do: k`. Thread the id into `center_terminal`, `machine_read`, `ensure_machine_coworker`, `resize_focused_terminal`. (One terminal per world, keyed by id — Decision 5.)
- `Space.fetch(:tlon)` (spawn_machine_coworker L1694; and any other) → `Space.fetch(state.active_key)`; thread `state`/`active_key` into these helpers. Guard the `nil` return (funes-down mid-spawn → no-op, like today's failed spawn).
- `machine_thread_id`/`standing_thread_id` logic unchanged (thread identity, not space key).

**Files:**
- Modify: `lib/aleph/cockpit.ex` (all sites above)
- Modify: `lib/aleph/keymap.ex` — `handle(key, %{active_key: :tlon, …})` (L202) → `when Space.world?(k)`; the type union `:tlon_enter`/`:tlon_preview` labels stay (they name center actions, not the key); **`command(Enter, %{active_key: :orbis})` (L264)** currently hardcodes `active_key: :tlon` — see Task C1.4.
- Modify: `lib/aleph/stack.ex:352`, `lib/aleph/crew.ex:68`, `lib/aleph/panel/chorus.ex:54` — see C1.4/C1.5.
- Test: `test/aleph/cockpit_test.exs`, `test/aleph/keymap_test.exs` (extend existing `:tlon`-keyed tests to assert against id `1`/`0`).

**Step 1 — failing test:** drive the cockpit into the world space by id and assert the render map still gates the World fields on. Example (adapt to the existing cockpit test harness):
```elixir
test "world-space render gates on world?/1, keyed by id" do
  state = build_state(active_key: 1)  # was :tlon
  reads = Cockpit.reads_for(state)     # or whatever the existing gate-assertion helper is
  assert reads.tlon_layout != nil
  assert reads.memory != nil
end
```
**Step 2 — run, expect FAIL/compile-error** (clauses no longer match an integer key).
**Step 3 — implement** the transformation rules across all sites. Add the private helpers `active_world_key/1`. Compile clean (`mise run aleph:check` catches an unconverted `:tlon` clause as an unreachable/failed match).
**Step 4 — run, expect PASS** + full aleph suite green.
**Step 5 — commit:** `aleph: cockpit keys the World space by world id, not :tlon`.

### Task C1.4: Enter-into-world switches to the *selected* world's id

`keymap.ex:264` (`command(Enter, %{active_key: :orbis})`) and `chorus.ex:54` (the survey-row Enter, `{:switch_space, :tlon}`) both hardcode `:tlon`. Enter on an Orbis survey row must switch to **that row's** world id.

**Files:**
- Modify: `lib/aleph/panel/chorus.ex` (~L54 — resolve the selected survey row to its world, emit `{:switch_space, world.id}`)
- Modify: `lib/aleph/keymap.ex:264` — the space-level Enter routes through the survey selection (emit `{:switch_space, id}` for the focused world row) rather than a literal `:tlon`
- Test: `test/aleph/panel/chorus_test.exs`, `test/aleph/keymap_test.exs`

**Step 1 — failing test:** with two worlds in the survey, Enter on the second row emits `{:switch_space, <second id>}`.
**Step 2 — run, expect FAIL.**
**Step 3 — implement:** thread the world list (`Aleph.Worlds.all/0`, already read for the survey) so the selected row index resolves to `Enum.at(worlds, i).id`. The cockpit handler for `{:switch_space, key}` already sets `active_key: key` (generalize if it pattern-matched `:tlon`).
**Step 4 — run, expect PASS.**
**Step 5 — commit:** `aleph: Orbis Enter switches to the selected world's id`.

### Task C1.5: un-`:tlon` the socket readers (still lead-derived for now)

`crew.ex:68` and `stack.ex:352` derive a tmux socket via `Profiles.socket(Space.fetch(:tlon).coworker)`. C1 only removes the `:tlon` literal (socket scheme still lead-name-derived; **C2** switches it to per-world-by-id).

**Files:**
- Modify: `lib/aleph/crew.ex:68`, `lib/aleph/stack.ex:352`
- Test: `test/aleph/crew_test.exs`, `test/aleph/stack_test.exs` (if present)

**Step 1-4:** thread the active world key to these call sites (or read the active world from the caller); `Space.fetch(active_key)` with a `nil` guard. With one world, socket is unchanged (`aleph-tertius`).
**Step 5 — commit:** `aleph: socket readers fetch the active world, not :tlon`.

### Phase C1 DoD

- `mise run aleph:check` green; full aleph suite green.
- `grep -rn ":tlon" lib/` → **zero** (except the `:tlon_enter`/`:tlon_preview` *action* labels in keymap, which name center actions, not the space key — rename to `:world_enter`/`:world_preview` in this task if cheap).
- `grep -n "String.to_atom" lib/aleph/space.ex` → gone; only `char_key/1` remains in cockpit.
- **Live-verify (operator):** boot aleph, confirm Orbis↔Tlön still switches, tertius+hronir still spawn, nav/preview/attach unchanged — driven by id key `1`.

---

## Phase C2 — de-singleton the leader spawn (roster-driven cast)

Replace the three hardcoded spawners with one `ensure_world_roster(world)` reading `world.roster[]`. Each entry → `Profiles.instantiate/1` → launcher chosen by `harness`. Head does `new-session` (the embedded center), tail `new-window`. Mention routing, tab presence, and the (now-retired) third-agent all derive from the roster.

### Task C2.1: `harness` field on the archetype registry

**Files:**
- Modify: `lib/aleph/profiles.ex` — add `harness:` to each `@archetypes` template + carry it on `%Profile{}` (struct + `instantiate/1`)
- Modify: `lib/aleph/profile.ex` (the struct) — add `field :harness, default: :pi`
- Test: `test/aleph/profiles_test.exs`

**Step 1 — failing test:**
```elixir
test "builder instantiates as a claude_code harness; surveyor as pi" do
  assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
  assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :pi
end
```
**Step 2 — run, expect FAIL.**
**Step 3 — implement:** `builder: %{harness: :claude_code, …}`, all others `harness: :pi`. `instantiate/1` sets `harness: t.harness`. Struct default `:pi` (a template without the key = pi).
**Step 4 — run, expect PASS.**
**Step 5 — commit:** `aleph: archetypes declare a launch harness (pi | claude_code)`.

### Task C2.2: per-world tmux naming (session `w<id>`, socket `aleph-world-<id>`)

**Files:**
- Modify: `lib/aleph/cockpit.ex` — replace `@tlon_session "tlon"` and `tlon_tmux/1`'s `Profiles.socket(Space.fetch(…).coworker)` with id-derived names: `world_session(id) = "w#{id}"`, `world_socket(id) = "aleph-world-#{id}"`. Thread the active world id through `tlon_run`/`tlon_tmux`/`tlon_tabs`/`spawn_*`.
- Modify: `lib/aleph/profiles.ex` — `profile_launcher/1` (or a new arity) takes the world id so `new-session` targets `world_session(id)` on `world_socket(id)`.
- Modify: `lib/aleph/crew.ex`, `lib/aleph/stack.ex` — socket now `world_socket(active_id)`.
- Test: `test/aleph/cockpit_test.exs` (inject `:aleph, :tlon_cmd` fake runner, assert argv carries `-L aleph-world-1` and `w1`).

**Step 1 — failing test:** a tmux query for world id 1 shells `tmux -L aleph-world-1 … w1 …`.
**Step 2-4:** implement; the fake-runner argv assertion (the existing `tlon_cmd` seam) proves it without live tmux.
**Step 5 — commit:** `aleph: per-world tmux session (w<id>) and socket (aleph-world-<id>)`.

### Task C2.3: `ensure_world_roster/1` replaces the three spawners

**Files:**
- Modify: `lib/aleph/cockpit.ex` — new `ensure_world_roster(state)`; delete `ensure_machine_coworker`/`ensure_claude_coworker`/`ensure_third_coworker` and the constants `@machine_agent`/`@machine_window`/`@claude_agent`/`@claude_window` (L54-68); keep the backoff machinery, now keyed per-instance.
- Test: `test/aleph/cockpit_test.exs`

**Design:**
```elixir
# The active world's roster spawns lazily on entry: head = the embedded center (new-session),
# tail = tmux windows (new-window). Each entry's launcher is chosen by its archetype harness.
defp ensure_world_roster(%{active_key: k} = state) when Aleph.Space.world?(k) do
  case Space.fetch(k) do
    %{roster: [lead | rest]} = space ->
      state
      |> ensure_center(k, lead)                 # was ensure_machine_coworker (head)
      |> ensure_windows(space, rest)            # was ensure_claude_coworker + third (tail)
    _ -> state                                   # empty roster / funes down → no-op
  end
end
defp ensure_world_roster(state), do: state
```
- `ensure_center(world_id, entry)`: `Profiles.instantiate(entry)` → `profile_launcher(profile, world_id)` (pi) — the head is always the embedded `Aleph.Terminal` keyed by `world_id`; backoff via the existing `machine_retry_at` (rename → `center_retry_at`).
- `ensure_windows(space, entries)`: for each entry absent from `tlon_tabs()`, spawn a window named `entry.name` via the harness-dispatched launcher:
```elixir
defp spawn_roster_window(space, %{name: name} = entry) do
  p = Profiles.instantiate(entry)
  case p.harness do
    :claude_code -> spawn_agent_window(handle(name), name, machine_thread_id(), space.id)  # real claude
    :pi          -> spawn_pi_window(p, name, space.id)                                       # pi --model …
  end
end
defp handle(name), do: "#{name}-machine"
```
(`spawn_pi_window` is new — a `new-window` running `pi_command(profile)`; the `:pi` tail path that `ensure_thread_sessions`' "pi-launched staffing is a follow-up" comment anticipated.)

**Step 1 — failing test:** a world with `roster: [{surveyor,"tertius"},{builder,"hronir"}]` drives `ensure_world_roster` → the fake runner sees a `new-session … w<id>` for tertius and a `new-window … -n hronir` running the claude launcher.
**Step 2-4:** implement; assert argv.
**Step 5 — commit:** `aleph: ensure_world_roster spawns a world's cast from its roster`.

### Task C2.4: mention routing derives from the roster

**Files:**
- Modify: `lib/aleph/mention.ex` — `@base_coworkers` (L25) and `third_agent/0` (L27-37) die; `coworkers/1` takes the active world's roster and builds `%{"#{name}-machine" => name}` (window = instance name now; `hronir`'s window is `hronir`, not a separate label). `TLON_MENTION_LABEL` anon knob stays.
- Modify: `lib/aleph/view.ex:317` (`window_tabs`) and any `Aleph.Mention.coworkers/0` caller — pass the active world's roster.
- Test: `test/aleph/mention_test.exs`

**Step 1 — failing test:** `Mention.mentions("@hronir-machine ping", roster)` resolves to `{"hronir-machine", "hronir"}` from a roster, with no `@base_coworkers`.
**Step 2-4:** implement; delete the env hatch + fixed map.
**Step 5 — commit:** `aleph: @-mention routing derives from the world roster`.

### Task C2.5: retire the singleton constants + `$TLON_THIRD_AGENT`

**Files:**
- Modify: `lib/aleph/cockpit.ex`, `lib/aleph/mention.ex`, `docs/tlon-experiments` — remove `@claude_agent`/`@claude_window`/`@machine_agent`/`@machine_window`, `third_agent/0`, `claude_launched?/third_agent_author` (the per-thread leaf spawn now checks the entry's harness). `ensure_thread_sessions`' `claude_launched?(lead)` gate generalizes to "is this thread's lead a `:claude_code` roster entry" (C3 refines leaf ownership).
- Test: existing tests updated; `grep` gate.

**Step 5 — commit:** `aleph: retire the tertius/hronir singleton constants and the third-agent env hatch`.

### Task C2.6: grow the seed roster to include the builder

The funes seed (`Funes.Release.seed_world`) currently seeds `roster: [{surveyor,"tertius"}]`. The live cast is tertius **+** hronir; C2 makes the roster the source of truth, so the seed must carry both or the builder never spawns.

**Files:**
- Modify: `modules/funes/lib/funes/release.ex` — `seed_world/0`'s roster → `[%{"archetype"=>"surveyor","name"=>"tertius"}, %{"archetype"=>"builder","name"=>"hronir"}]`; make it **backfill** an existing row (find-or-create is idempotent on *absence*, but row 1 already exists with the one-entry roster — add an `edit_world` when the stored roster lacks the builder, guarded so a hand-edited roster isn't clobbered).
- Test: `modules/funes/test/funes/release_test.exs` — seed twice, assert the row ends with both entries; a hand-edited roster is left alone.

**Step 5 — commit:** `funes: seed roster carries the builder (hronir)`. **Live:** operator runs `funes:restart` (re-seed) or `edit_world` on row 1.

### Phase C2 DoD

- aleph + funes suites green; `mise run aleph:check` green.
- `grep -rn "TLON_THIRD_AGENT\|@base_coworkers\|@machine_agent\|@claude_agent\|@tlon_session" lib/` → zero.
- **Live-verify (operator):** enter Tlön → tertius (pi center) + hronir (real claude window) spawn from the roster; `@hronir-machine`/`@tertius-machine` mentions route; the socket is `aleph-world-1`. Adding a third roster entry via `edit_world` spawns a third window with no code change.

---

## Phase C3 — tabs = leaders, Leaves panel = leaves (attach + leader-grouping)

### Task C3.1: WindowBar shows leader windows only

**Files:**
- Modify: `lib/aleph/view.ex:317` (`window_tabs`) — partition `tlon_tabs()` into leaders (window name ∈ the world's roster names, plus the `uqbar` console furniture) vs leaves (`t<id>`); WindowBar gets leaders only.
- Modify: `lib/aleph/panel/window_bar.ex` — unchanged render; it just receives fewer tabs.
- Test: `test/aleph/view_test.exs` — tabs input with `tertius`/`hronir`/`t42` → WindowBar tabs exclude `t42`.

**Step 5 — commit:** `aleph: WindowBar shows leader windows only`.

### Task C3.2: Leaves panel lists `t<id>` leaves, grouped by leader

**Files:**
- Modify: `lib/aleph/panel/leaves.ex` — already renders leaf rows from `Aleph.Orbis.rollup/0` (`%{id, title, lead, status, conflicts}`). Add: when a leader is focused (from state), **sort that leader's leaves to the top** (stable sort: `own_leader?` desc, then existing order). `data` gains `focused_lead` (the active tab's instance handle), injected by the View.
- Modify: `lib/aleph/view.ex` — inject `focused_lead` into the Leaves panel data from the active WindowBar tab's agent.
- Test: `test/aleph/panel/leaves_test.exs` — leaves for the focused leader float to the top.

**Step 1 — failing test:** rows `[%{lead: "tertius"}, %{lead: "hronir"}, %{lead: "hronir"}]` with `focused_lead: "hronir-machine"` → the two hronir leaves render first.
**Step 2-4:** implement the stable partition.
**Step 5 — commit:** `aleph: Leaves panel floats the focused leader's leaves to the top`.

### Task C3.3: select-a-leaf attaches it in the center

The Leaves panel already attaches on Enter (re-points the tmux window — `leaves.ex` moduledoc). C3 makes the surface consistent: attaching a leaf sets `focused_session :: {:leaf, id}`; the center follows it (`tmux select-window` to `t<id>`); the WindowBar highlights **no** leader tab (the leaf isn't a tab), and the Leaves panel row washes `:selected`.

**Files:**
- Modify: `lib/aleph/cockpit.ex` — track `focused_session :: {:leader, name} | {:leaf, id}`; `center` selects that window; selecting a leader tab sets `{:leader, name}`, a leaf sets `{:leaf, id}`.
- Modify: `lib/aleph/keymap.ex` — leaf-nav (`j/k` in the Leaves panel) + Enter (attach) already partly exist (`handle_tlon`); wire Enter → `{:attach_leaf, id}`.
- Modify: `lib/aleph/panel/leaves.ex` — the selected/attached leaf row styling.
- Test: `test/aleph/cockpit_test.exs`, `test/aleph/keymap_test.exs`.

**Step 1 — failing test:** `{:attach_leaf, 42}` → the fake runner sees `select-window … :t42`; `focused_session == {:leaf, 42}`.
**Step 2-4:** implement.
**Step 5 — commit:** `aleph: select a leaf to attach it in the World center`.

### Task C3.4: `[` / `]` flip views within a pane (lazygit-style)

Cheap secondary-surface access without cluttering the primary. Scope for Slice 1: bind `[`/`]` to cycle the **right-column pane's** active view (e.g. Health ↔ Activity ↔ Leaves) so the operator surfaces the right panel without a mode change — the "surface the right things, hide the rest behind a bind" principle.

**Files:**
- Modify: `lib/aleph/keymap.ex` — `[`/`]` in world nav → `{:cycle_pane_view, -1|+1}`.
- Modify: `lib/aleph/cockpit.ex` — track the active right-pane view index; the View renders the selected one full-height.
- Modify: `lib/aleph/view.ex` — render the active view of a cycled pane group.
- Test: `test/aleph/keymap_test.exs`, `test/aleph/view_test.exs`.

> **Re-plan checkpoint:** C3.4's exact pane-group model (which panels cycle together, whether it applies to left+right or right only) is the least-settled piece — validate the interaction live after C3.1–C3.3 land before finalizing. If it grows, split into its own slice.

**Step 5 — commit:** `aleph: [ ] cycle the right-pane view (lazygit-style within-pane flip)`.

### Phase C3 DoD

- aleph suite + `mise run aleph:check` green.
- **Live-verify (operator):** `t<id>` leaves no longer appear in the tab strip; the Leaves panel lists them, the focused leader's floated to the top; Enter on a leaf shows it in the center; `[`/`]` flips the right-pane view.

---

## Definition of done (Phase C overall)

- C1–C3 green; aleph + funes suites + `mise run aleph:check` green; boundary intact.
- The cockpit is off `:tlon` entirely (id-keyed); entering **any** world spawns **that world's** roster (lead as center, peers as tabs, harness-dispatched); leaves live in the Leaves panel, leader-grouped, attach-to-view.
- The Phase-B carried risks are dissolved: no `String.to_atom` on world names (I1), id keys can't collide (I2), `Space.fetch` no longer silently defaults to Orbis (C2), the `:tlon` slug bridge is gone.
- **Unblocks Phase D** (author face): worlds are fully id-keyed and roster-driven, so runtime `register_world` from the UI yields a second enterable world with its own cast — the Slice-1 release bar.

## Carried forward to Phase D

- The author face must not let a rename break the active session — id-keying (C1) makes this safe, but verify the `world_edited` cache reload → picker rebuild keeps the active id valid (or resolves a deleted active world to Orbis explicitly).
- Per-instance `knobs`/`model` overrides in the author face flow through `Profiles.instantiate/1` (already supported) — no C-phase work, but the roster-editing UX settles here.
