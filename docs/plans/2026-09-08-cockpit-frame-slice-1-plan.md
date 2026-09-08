# Cockpit frame (UX slice 1) — implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Re-shape the cockpit into the shell's anatomy — one-line top bar, thin always-on left rail (workspaces + threads), a center of one or two panes (conversation | coworker terminal), one-line bottom bar, and a drawer that hosts today's lazygit panes — without changing what any panel renders.

**Architecture:** `Console.View.compose/3` (`modules/console/lib/console/view.ex`) turns the assembled reads + terminal size into a list of `{panel, data, rect}` placements; `Console.Cockpit.do_render/1` appends overlay placements (lazygit, boards, menu) and `Console.Board` paints. Slice 1 changes the placement math and adds two panels (TopBar, Rail) and one overlay (the drawer), reusing every existing rail panel unchanged. Panels implement `Console.Panel` (`topics/1`, `render/2`, optional `pick/3`, `hints/1`). Tests assert placements as data (`test/console/view_test.exs`), never pixels.

**Tech Stack:** Elixir, the console's own termbox2 painter, ExUnit. Gate: `mise run console:check` (format + 871 tests). Design: `docs/plans/2026-09-08-cockpit-ux-principles-design.md` §2, §5. Survey facts (2026-09-08): spine = `Panel.Sidebar` at `spine_width/1`; rail = `space.left` (`Activity, Crew, Memory, Stack`) at `div(w,4)`; center = `ThreadStack`/`Terminal` + `NewThread|Reply` + `Tertius`; session pane = `div(center_total,3)` when `reads[:session_pane]` is an integer; footer = `Panel.StatusBar`, `@status_h 2`; spaces in `Console.Space` (`:orbis` + workspaces); overlays appended in `Cockpit.do_render/1` (cockpit.ex ~1230) with input intercepted in `handle_cast` (~322-382); focus SM `Console.Tlon.Focus` walks `%{left: rail, right: [], sections: %{}}`.

Work on `main` in small commits (Andrew's rule). Run `cd modules/console && mise exec -- mix test <file>` per task and `mise run console:check` before each commit. Every commit message ends with the two attribution trailers used in this repo's recent history.

---

### Task 1: the top bar (one line) and a one-line footer

**Files:**
- Create: `modules/console/lib/console/panel/top_bar.ex`
- Modify: `modules/console/lib/console/view.ex` (`@status_h`, `compose/3` body_h + the `status` placement)
- Modify: `modules/console/lib/console/panel/status_bar.ex:203` (the default `render/2` — drop the info row, keep hints + flash/prompt faces)
- Test: `modules/console/test/console/view_test.exs`, `modules/console/test/console/panel/top_bar_test.exs`

**Step 1: failing tests**

```elixir
# test/console/panel/top_bar_test.exs
defmodule Console.Panel.TopBarTest do
  use ExUnit.Case, async: true
  alias Console.Panel.TopBar

  test "one row: workspace · thread and stage · coworker and warmth · link" do
    data = %{workspace: "Tlön", thread: "review PR 42", stage: "build", lead: "hronir", warm?: true, link: :up}
    [row] = TopBar.render(data, %{x: 0, y: 0, w: 80, h: 1})
    text = Console.Panel.row_text(row)   # the existing helper tests use for rows; if none, IO.iodata_to_binary over the cells' chars
    assert text =~ "Tlön"
    assert text =~ "review PR 42"
    assert text =~ "build"
    assert text =~ "hronir"
  end

  test "a down link is named, and nothing crashes on an empty workspace" do
    [row] = TopBar.render(%{link: :down}, %{x: 0, y: 0, w: 40, h: 1})
    assert Console.Panel.row_text(row) =~ "server down"
  end
end
```

In `view_test.exs` add to the existing `reads/1` helper nothing; add:

```elixir
describe "the frame's bars (UX slice 1)" do
  test "row 0 is the TopBar, the last row is a one-line StatusBar, the body is between" do
    boxes = View.compose(reads(%{}), 120, 40)
    assert {Panel.TopBar, _, %{x: 0, y: 0, w: 120, h: 1}} = Enum.find(boxes, &match?({Panel.TopBar, _, _}, &1))
    assert {Panel.StatusBar, _, %{x: 0, y: 39, w: 120, h: 1}} = Enum.find(boxes, &match?({Panel.StatusBar, _, _}, &1))
    body = for {p, _, r} <- boxes, p not in [Panel.TopBar, Panel.StatusBar], do: r
    assert Enum.all?(body, &(&1.y >= 1 and &1.y + &1.h <= 39))
  end
end
```

**Step 2:** `mise exec -- mix test test/console/panel/top_bar_test.exs test/console/view_test.exs` → FAIL (TopBar undefined; status rect is h: 2 at y: 38).

**Step 3: implement**

- `Panel.TopBar`: `@behaviour Console.Panel`; `topics(_), do: [Server.Bus.threads_topic(), Server.Bus.sessions_topic()]`; `render/2` builds one row: left = `workspace`, `·`, `thread` and `[stage]` when present; right-aligned = `lead` with a warmth glyph (`●` warm / `○` cold — reuse the glyphs `Panel.Roster` uses) and, when `link == :down`, `server down` in the alarm style. Use the row-building helpers `StatusBar` uses (clip to `rect.w`).
- `view.ex`: `@status_h 1`, `@top_h 1`; `body_h = max(h - @top_h - @status_h - composer_h, 1)`; every body rect gets `y: @top_h` (the `wide_columns/3` and the `:narrow` branch pass `y: 0` today — thread `@top_h` through); add `top = {Panel.TopBar, top_data(reads), %{x: 0, y: 0, w: w, h: 1}}`; return `[top | borders] ++ contents ++ composer ++ [status]`.
- `top_data/1`: `%{workspace: space.label, thread: reads.thread_stack[:opened_title], stage: ..., lead: ..., warm?: ..., link: link_state()}` — take thread/stage/lead from what `status_data/3` already computes for the old info row (move that code, do not duplicate). `link_state/0`: `if Console.Backend.impl() == Console.Backend.Remote and not Console.Backend.Link.up?(), do: :down, else: :up`.
- `StatusBar.render/2` default face (:203): remove the info row (mode chip, space label, HEALTH segment — HEALTH goes to the drawer in Task 4); render hints only. Flash / leader / typing faces stay one row each.

**Step 4:** tests pass. Fix the existing `view_test` cases that assert `y: h - 2` for the status bar and `y: 0` for body boxes (grep `h - 2` and `y: 0`).

**Step 5:** `mise run console:check` green → commit `feat(console): the frame's bars — a one-line TopBar (workspace · thread/stage · coworker warmth · server link) and a one-line footer (UX slice 1, task 1)`.

---

### Task 2: the rail — workspaces + threads, replacing spine and funes rail

**Files:**
- Create: `modules/console/lib/console/panel/rail.ex`
- Modify: `modules/console/lib/console/view.ex` (`compose/3` columns: `spine`/`rail` → one `rail`; `wide_columns/3`; `focused_section/3`)
- Modify: `modules/console/lib/console/reads.ex:586` (the `sidebar` read: add per-thread `warm?`, `awaiting`, `unread?`, `working?` — `Board.sidebar/0` already returns `working`, `awaiting`; warmth from `Console.Server.Staff.roster/0` or the sessions read `reads.ex` builds for ROSTER)
- Test: `modules/console/test/console/panel/rail_test.exs`, `view_test.exs`

**Step 1: failing tests**

```elixir
# rail_test.exs
test "workspaces then the active one's threads; one badge per row by priority" do
  data = %{groups: [%{workspace: %{id: 1, name: "Tlön"}, threads: [
             %{id: 9, title: "general", warm?: true, awaiting: "andrew", unread?: true, working: false},
             %{id: 8, title: "aleph", warm?: false, awaiting: nil, unread?: true, working: true}]}],
           active_key: 1, opened: 9}
  rows = Console.Panel.Rail.render(data, %{x: 0, y: 1, w: 24, h: 10})
  texts = Enum.map(rows, &Console.Panel.row_text/1)
  assert Enum.any?(texts, &(&1 =~ "Tlön"))
  assert Enum.any?(texts, &(&1 =~ "general" and &1 =~ "!"))    # waiting on you beats unread
  assert Enum.any?(texts, &(&1 =~ "aleph" and &1 =~ "•" and not(&1 =~ "!")))  # unread beats working
end

test "pick maps a thread row to {:open_thread, id} and a workspace row to {:switch_workspace, id}" do
  ...
end
```

`view_test.exs`:

```elixir
test "one rail: Panel.Rail is the only left box; space.left panels are NOT in the frame" do
  boxes = View.compose(reads(%{}), 120, 40)
  lefts = for {p, _, %{x: 0}} <- boxes, p not in [Panel.TopBar, Panel.StatusBar], do: p
  assert Panel.Rail in lefts
  refute Enum.any?(boxes, fn {p, _, _} -> p in [Panel.Sidebar, Panel.Activity, Panel.Crew, Panel.Memory, Panel.Stack] end)
  {_, _, rail} = Enum.find(boxes, &match?({Panel.Rail, _, _}, &1))
  assert rail.w == max(22, div(120, 5))
end
```

**Step 2:** run → FAIL.

**Step 3: implement**

- `Panel.Rail`: render workspace header rows (name; the active one heavy) each followed by its threads only for the active workspace (`data.active_key`); thread row = warmth glyph, title clipped, one badge chosen by `badge/1`: `awaiting` → `"!"`, `unread?` → `"•"`, `working` → `"…"`, else none. `pick/3`: row → `{:open_thread, id}` | `{:switch_workspace, id}` (mirror `Panel.Sidebar.pick/3`'s row bookkeeping). `hints/1`: `[{"j/k", "thread"}, {"⏎", "open"}, {"[ ]", "workspace"}]`. `topics/1`: threads + sessions + workspaces topics.
- `view.ex`: `rail = [Panel.Rail]`; `wide_columns/3` drops `spine`, `rail_w = w |> div(5) |> max(22) |> min(div(w, 3))`, `rail_x = 0`, `center_x = rail_w + 1`. `focused_section/3` gets `%{left: [Panel.Rail], ...}` when the drawer is closed (Task 4 extends). `:narrow` branch stacks `[Panel.Rail | center_panels]`.
- Keep `Panel.Sidebar` and the four rail panels' modules (the drawer hosts them in Task 4); only the frame stops placing them.

**Step 4:** tests pass; update `view_test`'s "the Slack sidebar" and "the funes rail" describes to the new shape (rename, don't delete: they now assert Rail).

**Step 5:** gate → commit `feat(console): one rail — workspaces and the active workspace's threads with warmth and a single badge, replacing the spine + funes rail (UX slice 1, task 2)`.

---

### Task 3: the center — two equal panes when a session is live, one when not

**Files:**
- Modify: `modules/console/lib/console/view.ex:244` (`wide_columns/3` right split) and `compose/3` (`session?`)
- Modify: `modules/console/lib/console/reads.ex` (the `session_pane` read: default ON when the opened thread's lead has a live session — `Console.Sessions.live?/1` or the sessions read; the Alt+\ toggle becomes an override stored in state as `:auto | true | false`)
- Modify: `modules/console/lib/console/cockpit.ex:991` (`toggle_session_pane` effect: cycle `:auto → false → true → :auto`)
- Test: `view_test.exs` "the toggleable right session pane" describe

**Step 1: failing tests**

```elixir
test "a live session splits the center in two equal panes; none → the conversation spans it" do
  on = View.compose(reads(%{session_pane: 42}), 120, 40)
  {_, _, c} = Enum.find(on, &match?({Panel.ThreadStack, _, _}, &1))
  {_, _, t} = Enum.find(on, &match?({Panel.Terminal, :session, _}, &1))
  assert abs(c.w - t.w) <= 1
  off = View.compose(reads(%{session_pane: nil}), 120, 40)
  refute Enum.any?(off, &match?({Panel.Terminal, :session, _}, &1))
end

test "with no live session the terminal's place shows the placeholder verb" do
  boxes = View.compose(reads(%{session_pane: nil, opened_thread: 9}), 120, 40)
  assert Enum.any?(boxes, &match?({Panel.Placeholder, %{verb: "s"}, _}, &1))
end
```

**Step 2:** FAIL (right_w is a third; no Placeholder).

**Step 3: implement**

- `wide_columns/3`: `right_w = div(center_total - 1, 2)`, `center_w = center_total - right_w - 1`.
- `Panel.Placeholder` (new, tiny): renders one centred dim line `"no live session — s spawns one"` from `%{verb: "s"}`; placed in the `right` rect only when a thread is opened and no session is live AND the terminal width allows two panes (`w >= 100`); otherwise the conversation spans.
- `reads.ex`: `session_pane:` resolves `state.session_pane` `:auto` → the opened thread's live session id or nil; `true`/`false` force.
- `cockpit.ex`: the toggle cycles; the footer hint reads the mode.

**Step 4:** pass. **Step 5:** gate → commit `feat(console): the center is two equal panes when the coworker is live — conversation | terminal — and one when not, with the spawn verb in the terminal's place (UX slice 1, task 3)`.

---

### Task 4: the drawer — today's rail panels and boards, over the center

**Files:**
- Create: `modules/console/lib/console/cockpit/drawer.ex`
- Modify: `modules/console/lib/console/cockpit.ex` (state `drawer: nil | atom`, `last_drawer: :memory`; `do_render/1` appends `Drawer.placements(state, w, h)` after the base frame and before the menu; a `handle_cast` clause ahead of general dispatch routes keys while `state.drawer` is set)
- Modify: `modules/console/lib/console/keymap.ex` (one chord toggles: `Alt+d`; the drawer's own keys: `Esc` close, `1-9`/`h l` switch pane, `j k Enter` to the pane's cursor via `Focus`)
- Modify: `modules/console/lib/console/cockpit/boards.ex` (`board_placements/1` folds into the drawer: `state.board` → `state.drawer in [:tickets, :notes]`)
- Modify: `modules/console/lib/console/tlon/focus.ex` (`focused_pane/2` receives `%{left: drawer_panes}` while the drawer is open)
- Test: `modules/console/test/console/cockpit/drawer_test.exs`, `keymap_test.exs`

**Step 1: failing tests**

```elixir
# drawer_test.exs
alias Console.Cockpit.Drawer
test "closed: no placements" do
  assert Drawer.placements(%{drawer: nil}, 120, 40) == []
end

test "open: a Border with the pane tabs over the CENTER rect only — never the rail or bars" do
  state = %{drawer: :memory, reads: reads_fixture(), focus: %Console.Tlon.Focus{}}
  [{Console.Panel.Border, border, rect} | content] = Drawer.placements(state, 120, 40)
  assert rect.x >= max(22, div(120, 5)) + 1     # right of the rail
  assert rect.y == 1 and rect.y + rect.h == 39    # between the bars
  assert Enum.map(border.tabs, &elem(&1, 0)) == ~w(now crew memory stack roster triage tickets notes health)
  assert Enum.any?(content, &match?({Console.Panel.Memory, _, _}, &1))
end

test "the pane order is fixed and each atom maps to one panel" do
  assert Drawer.panel(:memory) == Console.Panel.Memory
  assert Drawer.panel(:tickets) == Console.Panel.TicketBoard
end
```

`keymap_test.exs`:

```elixir
test "Alt+d opens the drawer on its last pane and Alt+d / Esc close it" do
  {s1, _} = Keymap.handle(alt(:d), state(%{drawer: nil, last_drawer: :stack}))
  assert s1.drawer == :stack
  {s2, _} = Keymap.handle(key(:esc), s1)
  assert s2.drawer == nil and s2.last_drawer == :stack
end

test "in the drawer h/l walk the panes and j/k move the pane cursor" do ...
```

**Step 2:** FAIL.

**Step 3: implement**

- `Drawer.panes/0`: `[now: Panel.Activity, crew: Panel.Crew, memory: Panel.Memory, stack: Panel.Stack, roster: Panel.Roster, triage: Panel.Triage, tickets: Panel.TicketBoard, notes: Panel.NoteBoard, health: Panel.Health]`. `placements/3`: the center rect (recompute with the same `wide_columns` math — expose `View.center_rect/2`), one `Border` with `tabs` (the existing Border tab strip; active = `state.drawer`), then the pane's content placement inset by 1 with `Focus` slice for cursor/selection (reuse `View.content_for/4` — make it public).
- `Cockpit`: state fields; `do_render` order: base frame → lazygit → drawer → menu. Input: while `state.drawer`, a clause before general dispatch calls `Keymap.handle_drawer/2`; Esc/`Alt+d` close; `Enter` on STACK opens lazygit as today (`open_lazygit/1`); `Enter` on a MEMORY fact opens the Detail *inside the drawer* (Detail replaces the pane content until Esc).
- `Boards`: `state.board` removed; the spine tiles that opened boards are gone with the spine (Task 2); the `t`/`N` verbs that opened boards now set `drawer: :tickets | :notes`.
- `Focus`: `focused_pane(focus, %{left: Drawer.pane_modules(), right: [], sections: ...})` when open; the rail is not walkable while the drawer is open (the drawer has focus by definition).

**Step 4:** pass; `keymap_test` board-overlay tests migrate to drawer semantics.

**Step 5:** gate → commit `feat(console): the drawer — NOW · CREW · MEMORY · STACK · ROSTER · TRIAGE · TICKETS · NOTES · HEALTH behind Alt+d over the center, Esc closes; the board overlays fold into it (UX slice 1, task 4)`.

---

### Task 5: retire Orbis/Home as a space; workspaces are the only spaces

**Files:**
- Modify: `modules/console/lib/console/space.ex:63` (`all/0` = workspaces; `orbis_space/0` deleted)
- Modify: `modules/console/lib/console/keymap.ex` (`Tab`/`Shift+Tab` cycle workspaces; `Alt+Shift+digit` stays; Orbis-only clauses deleted)
- Modify: `modules/console/lib/console/cockpit.ex` (initial `active_key` = first workspace; `orbis_*` state fields removed; `Panel.Author` reached from the drawer as `:config` — add `config: Panel.Author` to `Drawer.panes/0`)
- Modify: `modules/console/lib/console/view.ex` (`detail_open?`/`orbis_face` branch deleted)
- Delete: `modules/console/lib/console/panel/overview.ex` and its test (the per-workspace rollup is the drawer's TRIAGE + the rail now; keep `Console.Orbis` reads that other panes use)
- Test: `keymap_test.exs` (Orbis cases → workspace cycling), `cockpit_workspaces_test.exs`, `space_test.exs`

**Step 1:** write the failing tests: `Space.all/0` has no `:orbis`; `Tab` from workspace 1 with two workspaces lands on workspace 2 and wraps; `Alt+d` then `l` ×N reaches `:config` and it renders `Panel.Author`.

**Step 2:** FAIL. **Step 3:** implement per the file list; grep `:orbis` across `lib/` and `test/` until empty. **Step 4:** pass, gate green.

**Step 5:** commit `refactor(console): workspaces are the only spaces — Home/Orbis retired (rail + top bar are the overview, the drawer's TRIAGE the rollup), Author lives in the drawer as config (UX slice 1, task 5)`.

---

### Task 6: the live pass and the docs

**Files:**
- Modify: `modules/console/README.md` / `AGENTS.md` (the frame section; keys: `Alt+d` drawer, `Alt+\` session pane cycle, Tab workspaces)
- Modify: `docs/plans/2026-09-08-cockpit-ux-principles-design.md` (status line: slice 1 built)

**Steps:**
1. `mise run console:check` green; `mise run console:run` in ghostty (the tlon service must be up).
2. Andrew's eye-pass checklist: top bar reads workspace/thread/coworker/link; rail lists workspaces then threads with one badge each; opening a thread with a warm coworker shows two equal panes; `Alt+\` cycles; `Alt+d` opens the drawer over the center only, `h/l` walk the tabs, Esc closes, rail and bars stay put; Tab cycles workspaces; no Home anywhere.
3. Fix what the pass finds, one commit each.
4. Commit the docs: `docs(console): the frame after UX slice 1`.

---

## Out of scope (later slices)

Key layers and the switcher (slice 2 — `Ctrl+Space`/TERM-NAV stay as they are in slice 1), message kinds (3), ticket links (4), workspace tables (5), tertius' second door to posting (slice 2). The Notes-reimagined backlog stands.
