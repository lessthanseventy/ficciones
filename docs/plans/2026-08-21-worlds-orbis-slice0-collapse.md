# Worlds/Orbis Slice 0 — The Collapse — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Collapse aleph's three fixed spaces into the two-space skeleton the reshape aims at — Orbis (god-view survey) over a single hardcoded World (Tlön) — by deleting Sessions, folding its `attach` into a selection-driven center re-point, and re-pointing the survey from threads to worlds. UX-first, almost no new backend; proves the skeleton before Slice 1's config-truth work.

**Architecture:** The picker keeps two entries — Orbis and Tlön-the-World. Sessions dies: its per-thread native-PTY center is removed, and `attach` becomes a *selection-driven re-point* of the World's existing tmux center (preview on hover, commit + focus on Enter). Orbis' Chorus is re-pointed to a per-**world** rollup (one hardcoded world today). No `world` domain model, no funes-owned compositions, no author face — all Slice 1.

**Tech Stack:** Elixir, aleph TUI (`modules/aleph`), `Aleph.Space`/`Aleph.Cockpit`/`Aleph.Keymap`/`Aleph.Tlon.Focus`, tmux (`select-window` re-point), ghostty embedded VT, ExUnit. Sibling `modules/funes` (`Funes.Channel`, `Funes.Board`) read-only here.

---

## Assumptions & the one real fork (read before executing)

These are my calls given the design doc + the live code maps. Each is cheap to reverse at a review checkpoint; flag disagreement before the task that depends on it.

- **A1 — The World center stays a single tmux client.** "Attach in place" = re-point that center with `tmux select-window` (the primitive already exists: `cockpit.ex select_tlon_window/1`). No polymorphic native-PTY center in Slice 0.
- **A2 — Preview-swap (tweak #1) targets the Leaves pane** (a leaf whose `lead` maps to a live World window). Arrow-hover = `select-window` re-point only (no keys, no focus); Enter/typing = commit (`in_terminal?: true`, keys flow). *Revised in Task 1: WindowBar/Leaders is a `surface` frame, NOT a navigable focus column, so the focus SM cannot land on it — Leaves is the only window-bearing nav pane today.* `previewed_window` holds the **tmux string index** (`"1"`), tmux-native; no int conversion.
- **A3 — Arbitrary-leaf attach is explicitly deferred to Slice 1.** A Leaves row whose lead does not map to a live World window flashes `no live session (Slice 1)`. We do NOT fake a native per-thread PTY — that path is what Sessions provided and what we're deleting.
- **A4 — "One hardcoded world" = Tlön stays a hardcoded space, reframed as World #1.** No `world` struct; the rollup gains a single hardcoded world grouping key. Full config-truth (funes-owned compositions, flake seeding) is Slice 1.
- **A5 — "tertius re-seats as Orbis' resident agent" is a framing change, not a new PTY.** tertius already runs the root machine thread (`machine_chat/loop.ex`); Orbis' survey is its home view. Orbis gains no center terminal in Slice 0.
- **A6 — Settings modal stays as-is.** Author face deferred to Slice 1 (operator confirmed).

**The fork, stated plainly:** if you (operator) want the World center to be able to show an *arbitrary leaf's own PTY* (not just its tmux windows) in Slice 0, that's a bigger backend change (a per-world roster→PTY registry) and A1–A3 are wrong. Default is: no, that's Slice 1.

---

## Task 1: Selection-driven center re-point (preview-swap, tweak #1) on the World

Build the "preview-follows-selection, commit-on-Enter" primitive against the World's existing tmux center. This is the `attach` mechanism the rest of the slice reuses.

**Files:**
- Modify: `modules/aleph/lib/aleph/tlon/focus.ex` (add a `preview` notion — the pane+cursor that drives the center in nav mode)
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (on nav-cursor move over Leaders/Leaves, re-point the tmux center via `select_tlon_window/1`; keep keys/focus gated on commit)
- Modify: `modules/aleph/lib/aleph/keymap.ex` (nav-mode `j/k/Up/Down` over a window-bearing pane emits a `:preview` effect; `Enter` commits)
- Test: `modules/aleph/test/aleph/tlon/focus_test.exs`, `modules/aleph/test/aleph/cockpit_preview_test.exs` (new)

**Step 1 — Write the failing test (preview re-points, does not focus):**

```elixir
# test/aleph/cockpit_preview_test.exs
test "arrow over a Leaders/Leaves row re-points the center window but stays in nav mode" do
  state = tlon_state(windows: ~w(tertius hronir uqbar), focus_on: Panel.WindowBar, cursor: 0)
  {:noreply, next} = Cockpit.apply_effect({:preview, 1}, state)   # move to window index 1
  assert next.previewed_window == 1
  assert next.focus.in_terminal? == false                         # NO focus steal
  assert_received {:tmux, ["select-window", "-t", "tlon:1"]}       # re-point happened
end

test "Enter commits: focuses the previewed window and drops into the terminal" do
  state = %{tlon_state() | previewed_window: 1}
  {:noreply, next} = Cockpit.apply_effect(:tlon_enter_leaders, state)
  assert next.focus.in_terminal? == true
end
```

**Step 2 — Run to verify it fails** (`mise exec -- mix test test/aleph/cockpit_preview_test.exs` → FAIL: `:preview`/`previewed_window` undefined).

**Step 3 — Implement:** add `previewed_window` to cockpit state; a `apply_effect({:preview, idx}, state)` clause that calls `select_tlon_window(%{index: idx})` and stores `previewed_window` WITHOUT touching `focus.in_terminal?`; a commit clause that sets `in_terminal?: true`. In `keymap.ex handle_tlon`, when nav cursor moves over a window-bearing pane (WindowBar/Leaves), emit `{:preview, resolved_index}` alongside the existing `:item_next/:item_prev` focus move. Reuse `window_index/2` (`cockpit.ex:611`) to map a Leaves row's lead → window index; unmapped → no re-point.

**Step 4 — Run tests to verify pass.**

**Step 5 — Commit:** `aleph: selection-driven center re-point (preview-swap) on the Tlön world`

---

## Task 2: Rewire Leaves `Enter` off the (soon-deleted) Sessions space

`jump_to_leaf/2` (`cockpit.ex:874`) currently sets `active_key: :sessions` + `focused_id`. Retarget it to the Task 1 attach primitive.

**Files:**
- Modify: `modules/aleph/lib/aleph/cockpit.ex:874-884` (`jump_to_leaf/2`)
- Test: `modules/aleph/test/aleph/cockpit_leaves_attach_test.exs` (new)

**Step 1 — Failing test:**

# NOTE: jump_to_leaf must PREVIEW then COMMIT (re-point + focus) — reuse
# preview_focused/1 then commit_preview/1 from Task 1. previewed_window is a
# tmux STRING index ("1"), not an int.
```elixir
test "Enter on a leaf mapped to a live world window attaches it (commit + focus)" do
  state = tlon_state(windows: ~w(tertius hronir), leaves: [%{id: "t1", lead: "hronir"}], cursor: 0)
  {:noreply, next} = Cockpit.apply_effect(:tlon_enter, %{state | focus: focus_on(Panel.Leaves)})
  assert next.previewed_window == "1"        # hronir's window (tmux string index)
  assert next.focus.in_terminal? == true
end

test "Enter on a leaf with no live window flashes a Slice-1 deferral, no crash" do
  state = tlon_state(windows: ~w(tertius), leaves: [%{id: "t9", lead: "ghost"}], cursor: 0)
  {:noreply, next} = Cockpit.apply_effect(:tlon_enter, %{state | focus: focus_on(Panel.Leaves)})
  assert next.flash =~ "no live session"
end
```

**Step 2 — Verify fail** (still sets `active_key: :sessions`).

**Step 3 — Implement:** rewrite `jump_to_leaf/2` to look up the leaf under the cursor, map `leaf.lead → window_index`, and on hit call the commit path from Task 1; on miss set `flash: "no live session (Slice 1)"`. Remove the `active_key: :sessions` write.

**Step 4 — Verify pass.**

**Step 5 — Commit:** `aleph: Leaves Enter attaches via world-window select, not the Sessions space`

---

## Task 3: Delete the Sessions space and its dead clauses

With no remaining reference to `:sessions`, remove it. (Map of every ref: `space.ex:65`, `cockpit.ex:879`(gone after Task 2)/`1041`/`1080`, `keymap.ex:267`.)

**Files:**
- Modify: `modules/aleph/lib/aleph/space.ex:65-77` (delete the `:sessions` struct)
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (delete `terminal_read(%{active_key: :sessions})` @1041, `center_terminal(%{active_key: :sessions})` @1080)
- Modify: `modules/aleph/lib/aleph/keymap.ex:267` (delete the Sessions-only `enter_or_spawn` guard)
- Test: `modules/aleph/test/aleph/space_test.exs`

**Step 1 — Failing test:**

```elixir
test "the picker offers exactly Orbis and Tlön; Sessions is gone" do
  assert Enum.map(Space.all(), & &1.key) == [:orbis, :tlon]
end
test "Tab from Orbis lands on Tlön (no Sessions in between)" do
  assert Space.next(:orbis).key == :tlon
  assert Space.next(:tlon).key == :orbis
end
```

**Step 2 — Verify fail** (list is `[:orbis, :sessions, :tlon]`).

**Step 3 — Implement** the deletions. Grep-gate: `grep -rn ':sessions' modules/aleph/lib` must return nothing.

**Step 4 — Run `mise run aleph:check`** (full suite — catches any dead-clause fallout). Expected: green.

**Step 5 — Commit:** `aleph: delete the Sessions space — attach folded into the world center`

> Note: `Aleph.Sessions` (native per-thread PTY spawn) is now unreferenced but NOT deleted here — its teardown is a separate reversible follow-up, out of Slice 0 scope. Leave a `# UNREFERENCED since Slice 0 collapse — teardown TBD` marker at its moduledoc.

---

## Task 4: Re-point the rollup from threads to a (single, hardcoded) world

Orbis' survey face shows a row per **world**, not per thread. With one world, that's one row that carries the existing leads/open/stalled/done/trouble rollup for all its leaves.

**Files:**
- Modify: `modules/aleph/lib/aleph/orbis.ex` (`rollup/0` → group its per-thread rows under a single hardcoded world header)
- Modify: `modules/aleph/lib/aleph/panel/chorus.ex` (header `ORBIS · worlds`; render the world row + its rollup summary)
- Modify: `modules/aleph/lib/aleph/view.ex:207` (`data_for(Panel.Chorus, ...)` — feed the world rollup)
- Test: `modules/aleph/test/aleph/orbis_test.exs`, `modules/aleph/test/aleph/panel/chorus_test.exs`

**Step 1 — Failing test:**

```elixir
test "rollup groups leaves under a single hardcoded world" do
  r = Aleph.Orbis.rollup()
  assert [%{world: "Tlön", summary: %{open: _, stalled: _, done: _}, leaves: leaves}] = r.worlds
  assert is_list(leaves)
end
```

**Step 2 — Verify fail** (rollup returns `%{summary, rows}`, no `worlds`).

**Step 3 — Implement:** wrap the current `rows` under a hardcoded `%{world: "Tlön", summary: ..., leaves: rows}` in a `worlds: [...]` list. Keep the old `summary`/`rows` keys during transition if any caller still needs them (`panel/leaves.ex`, `machine_chat/loop.ex:117`) — or update those callers in the same task. Chorus renders `ORBIS · worlds` + one world row + summary line; `Enter` on a world zooms to its lens (switch to `:tlon`).

**Step 4 — Verify pass; run `mise run aleph:check`.**

**Step 5 — Commit:** `aleph: Orbis survey face — rollup grouped by world (one hardcoded world)`

---

## Task 5: Reframe Tlön as World #1 + tertius as Orbis' resident agent

Framing/labels only (per A4/A5). No PTY moves.

**Files:**
- Modify: `modules/aleph/lib/aleph/space.ex` (Tlön label/moduledoc → "World #1"; note the special-casing is provisional, Slice 1 moves it to funes composition data)
- Modify: `modules/aleph/lib/aleph/orbis.ex` moduledoc (tertius = Orbis' resident surveyor)
- Test: none new (doc/label); `mise run aleph:check` covers compile.

**Step 1–4:** update text; `mise run aleph:check` green.

**Step 5 — Commit:** `aleph: reframe Tlön as World #1, tertius as Orbis' resident surveyor`

---

## Definition of done

- `mise run aleph:check` green; `modules/funes` `mix test` green (no funes changes, but the reads are exercised).
- The picker offers exactly **Orbis** and **Tlön**; `grep -rn ':sessions' modules/aleph/lib` is empty.
- In Tlön nav mode, arrowing over Leaves **previews** (center re-points, no keys/focus); `Enter`/typing **commits** (focus + keys). A leaf with no live window flashes the Slice-1 deferral, no crash.
- Orbis' survey renders a **per-world** row (one hardcoded world) with its leads/open/stalled/done/trouble rollup; `Enter` zooms to the world.
- **Live-verify** (not just tests): boot `mise run aleph:run`, confirm Orbis↔Tlön cycle, preview-swap, and the survey row on real funes traffic.
- The two already-shipped interaction tweaks (nav-to-SPACES, heavy focused border) remain green and untouched.

## Deferred to Slice 1 (explicitly not in this plan)

- funes-owned world compositions + author face (Settings absorption) + a real second world (the release bar).
- Arbitrary-leaf attach via a per-world roster→PTY registry (the A1–A3 fork's "other" branch).
- `Aleph.Sessions` native-PTY module teardown.
- Per-world type/panel-sets (code vs life vs blank).
