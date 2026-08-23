# Aleph Cockpit Clarity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the cockpit's interaction model visible and reachable: numbered border titles, a
Health-pinned tabbed carousel (CREW default), a contextual footer driven by `Panel.hints/1`,
global `Alt+` chords + LOCK mode, semantic `y` yank over OSC 52, and the `Aleph.Graphics` kitty
seam.

**Architecture:** Everything rides the existing pure pipeline: `Aleph.View.compose/3` (reads →
placements) → `Aleph.Board` (placements → cells → termbox paint), keys through the pure
`Aleph.Keymap` reducer + `Aleph.Tlon.Focus` SM, side effects interpreted by the `Aleph.Cockpit`
GenServer. Each slice extends a pure layer first (testable headless), then does minimal cockpit
wiring. Design doc: `docs/plans/2026-08-23-aleph-cockpit-clarity-design.md`.

**Tech Stack:** Elixir (OTP 28 via mise), ExUnit, termbox2 NIF, tmux, kitty terminal protocols
(CSI-u keyboard, OSC 52, kitty graphics APC).

---

## Codebase primer (read this first)

All work is in `modules/aleph/`. Run everything from there through mise (OTP 28 — bare OTP 27
will bite you):

```bash
cd /home/andrew/projects/ficciones/modules/aleph
mise exec -- mix test                       # full suite
mise exec -- mix test test/aleph/view_test.exs   # one file
mise run aleph:check                        # the slice gate: format + warnings-as-errors + tests (run from repo root OR modules/aleph)
```

Key modules (all under `modules/aleph/lib/aleph/`):

- `view.ex` — **`View.compose(reads, w, h)`**: pure layout. Builds columns of "sections"
  (panel modules), wraps each in a `Panel.Border` placement + a content placement at an inset
  rect, appends `Panel.StatusBar` at the bottom. `data_for/2` maps panel → its slice of `reads`.
- `panel.ex` — the `Aleph.Panel` behaviour: `topics/1`, `render/2` (data + rect → styled rows =
  lists of `{text, style_atom}` runs), optional `pick/3` (click → action). Helpers: `line/2`,
  `blank/0`, `clip/2`, `pad/3`, `row_width/1`, `item_at/2`, `content_height/3`.
- `panel/border.ex` — the frame drawn UNDER each section (content paints over the interior).
  `%{focused: true}` → heavy `╔═╗` frame in `:accent`; else thin `╭─╮` in `:separator`.
- `panel/status_bar.ex` — the 2-row footer (info line + hints line). Has modal clauses
  (`:compose`, `:new_thread`, …, `flash`, `leader_pending?`) that stay untouched, and a default
  clause whose hint tables we replace.
- `keymap.ex` — **pure reducer** `handle(key_event, state) → {state, effect}`. Clause order is
  load-bearing: input-modal clauses first, then the World/Tlön routing clause (`handle_tlon`),
  then leader clauses, then `center_live?` forwarding, then the bare `command/2` table.
- `tlon/focus.ex` — `Aleph.Tlon.Focus`, the pure focus SM (`in_terminal?`, `column`, `pane`,
  `section`, per-pane `cursors`, `detail?`). Navigates a `layout` map
  `%{left: [pane], right: [pane], sections: %{}, counts: %{}}` derived per keypress by the
  cockpit (`tlon_layout/1`).
- `space.ex` — `Aleph.Space`: a space is plain data (`surface`, `left`, `right` panel lists).
  World spaces: `left: [Stack, Memory]`, `right: [Health, Crew, Activity, Leaves]`; View
  prepends `Panel.Spaces` to the left column. `Space.world?/1` is a **defguard** — callers
  `require Aleph.Space`.
- `cockpit.ex` (2500 lines) — the GenServer. Relevant parts: `init/1` (state map ~line 226),
  `handle_cast({:dispatch, key})` (~line 374, derives `center_live?`/`composer_thread_id`/
  `tlon_layout`/`author_worlds` per keypress and hands to Keymap), mouse dispatch (~line
  403–431, 750–830), `apply_effect/2` clauses (~line 856+), `render/1` (~line 1334 — assembles
  `reads`, calls `View.compose`, paints via `Board`), `tlon_layout/1` (~line 1528),
  `cycle_pane_view/2` (~line 988), `tlon_detail/2` (~line 1571).
- `style.ex` — the one palette; panels use semantic atoms only.
- `mouse.ex` — pure mouse routing; `hit_panel/3` skips `@chrome [Border, StatusBar]`.
- `board.ex` — rows → cells → termbox. `safe_rows` rescues panel crashes into an error row.

Conventions:
- Comments: terse, load-bearing "why" only (house rule — see `comment-style-terse` feedback).
- Tests are headless/pure; look at `test/aleph/view_test.exs` and
  `test/aleph/keymap_test.exs` for the idiom (literal state maps, no GenServer).
- Commit messages: `aleph: <what>`. **Use `git commit -F <file>` (never `-m` with backticks)**
  and end with a `Co-Authored-By:` trailer naming the model that ACTUALLY wrote the commit
  (e.g. `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`).

**Branch:** create `aleph-cockpit-clarity` off the current branch before Task 1.1:

```bash
cd /home/andrew/projects/ficciones && git checkout -b aleph-cockpit-clarity
```

**Slice gate:** after the last task of every slice run `mise run aleph:check` and fix anything
it flags before committing. Slices are ordered; tasks within a slice are ordered.

---

# Slice 1 — Border titles + digits + Memory collapse

Outcome: every section box carries its title (and a jump digit) ON the frame —
`╭ 2 STACK ───╮` — the panels' in-content header+blank rows die, and Memory's empty HABITS
section collapses to nothing.

### Task 1.1: Border learns titles, digits, tabs, hints

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/border.ex`
- Test: `modules/aleph/test/aleph/panel/border_test.exs` (create)

**Step 1: Write the failing tests**

Create `test/aleph/panel/border_test.exs`:

```elixir
defmodule Aleph.Panel.BorderTest do
  @moduledoc """
  The on-frame section label (design 2026-08-23): digit-first titles, the carousel tab strip,
  the bottom-corner hint — and tab_at_x/2 agreeing with what render/2 draws.
  """
  use ExUnit.Case, async: true

  alias Aleph.Panel
  alias Aleph.Panel.Border

  defp rect(w \\ 20, h \\ 5), do: %{x: 0, y: 0, w: w, h: h}

  defp row_text(row), do: row |> Enum.map(fn {t, _s} -> t end) |> Enum.join()

  test "a plain border (no title) renders the bare frame" do
    [top | _] = Border.render(%{focused: false}, rect())
    assert row_text(top) == "╭" <> String.duplicate("─", 18) <> "╮"
  end

  test "title + digit are punched into the top rule, digit first" do
    [top | _] = Border.render(%{focused: false, digit: 2, title: "STACK"}, rect())
    assert row_text(top) =~ "╭─ 2 STACK ─"
    assert String.length(row_text(top)) == 20
  end

  test "the focused frame is heavy and the title rides it" do
    [top | _] = Border.render(%{focused: true, digit: 2, title: "STACK"}, rect())
    assert row_text(top) =~ "╔═ 2 STACK ═"
  end

  test "a title too wide for the box is dropped, keeping the corners" do
    [top | _] = Border.render(%{focused: false, digit: 1, title: "MUCHTOOLONG"}, rect(8))
    assert row_text(top) == "╭──────╮"
  end

  test "tabs render as a strip — active lit (:header), siblings dim" do
    data = %{focused: false, digit: 5, tabs: [{"CREW", true}, {"ACT", false}]}
    [top | _] = Border.render(data, rect(30))
    assert row_text(top) =~ " 5 CREW · ACT "
    assert {"CREW", :header} in top
    assert {"ACT", :dim} in top
  end

  test "a hint renders right-aligned on the bottom rule" do
    rows = Border.render(%{focused: false, hint: "[ ] cycle"}, rect(20))
    bottom = List.last(rows)
    assert row_text(bottom) =~ "[ ] cycle ─╯" == false
    assert row_text(bottom) =~ " [ ] cycle "
    assert String.ends_with?(row_text(bottom), "╯")
    assert String.length(row_text(bottom)) == 20
  end

  test "tab_at_x maps a top-row x to the tab index render drew there" do
    data = %{focused: false, digit: 5, tabs: [{"CREW", true}, {"ACTIVITY", false}, {"LEAVES", false}]}
    [top | _] = Border.render(data, rect(40))
    text = row_text(top)

    for {label, i} <- Enum.with_index(["CREW", "ACTIVITY", "LEAVES"]) do
      {x, _len} = :binary.match(text, label)
      # byte offset == grapheme offset here except for the leading ╭ (3 bytes, 1 grapheme)
      gx = String.length(String.slice(text, 0, x) |> to_string())
      gx = text |> String.graphemes() |> Enum.take_while(&(&1 != String.first(label))) |> length()
      assert Border.tab_at_x(data, gx) == i
    end

    assert Border.tab_at_x(data, 0) == nil
  end

  test "nil data still renders the plain thin frame (legacy callers)" do
    [top | _] = Border.render(nil, rect())
    assert row_text(top) =~ "╭"
  end
end
```

> Note on the `tab_at_x` test: locating the label by grapheme offset via
> `Enum.take_while` only works when the label's first grapheme is unique in the row prefix —
> CREW/ACTIVITY/LEAVES satisfy that here ("C"/"A"/"L" don't appear earlier). Simplify if it
> fights you: hardcode the expected x offsets (`3 + String.length("5 ")` for the first tab,
> then `+ label + 3` per step) — the point is agreement between the two functions.

**Step 2: Run to verify failure**

Run: `mise exec -- mix test test/aleph/panel/border_test.exs`
Expected: FAIL (Border.render/2 with a `%{title: ...}` map raises or draws no title;
`tab_at_x/2` undefined).

**Step 3: Implement**

Replace `lib/aleph/panel/border.ex` body (keep the module + `@behaviour`; update the moduledoc
to mention on-frame labels):

```elixir
defmodule Aleph.Panel.Border do
  @moduledoc """
  A rounded box that frames a section, with the section's identity ON the frame (design
  2026-08-23): `╭─ 2 STACK ───╮` — jump digit first, then the title, or a carousel tab strip
  (`5 CREW · ACTIVITY · LEAVES`, active tab lit), plus an optional right-aligned hint on the
  bottom rule. Rendered *under* the panel it wraps — `Aleph.View` places the border first and
  the content at an inset rect. `%{focused: true}` swaps to a heavy double rule in `:accent`
  (the lazygit active-pane cue, legible on shape alone).
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  @thin {"╭", "╮", "╰", "╯", "─", "│"}
  @heavy {"╔", "╗", "╚", "╝", "═", "║"}

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(data, rect) when is_map(data) do
    focused? = data[:focused] == true
    frame = if focused?, do: :accent, else: :separator
    glyphs = if focused?, do: @heavy, else: @thin
    box(rect, frame, glyphs, label_runs(data, focused?), hint_runs(data))
  end

  def render(_data, rect), do: box(rect, :separator, @thin, [], [])

  @doc """
  Which carousel tab a click at top-row local `x` lands on (index into `data.tabs`), or nil.
  Mirrors the offsets `label_runs/2` draws (the WindowBar `tab_at_x` idiom) so the clickable
  regions can't drift from the paint; the border_test pins the agreement.
  """
  @spec tab_at_x(term(), non_neg_integer()) :: non_neg_integer() | nil
  def tab_at_x(%{tabs: tabs} = data, x) when is_list(tabs) and tabs != [] do
    # corner + 1 rule char + the leading space + the digit run ("5 ").
    first = 3 + digit_width(data)

    tabs
    |> Enum.with_index()
    |> Enum.reduce_while(first, fn {{label, _active?}, i}, s ->
      e = s + String.length(label)
      if x >= s and x < e, do: {:halt, {:hit, i}}, else: {:cont, e + 3}
    end)
    |> case do
      {:hit, i} -> i
      _ -> nil
    end
  end

  def tab_at_x(_data, _x), do: nil

  defp digit_width(%{digit: d}) when is_integer(d), do: String.length("#{d} ")
  defp digit_width(_data), do: 0

  # ` 2 STACK ` (digit first — the Alt+digit jump affordance) or the tab strip; [] → bare rule.
  defp label_runs(data, focused?) do
    title_style = if focused?, do: :accent, else: :header

    body =
      cond do
        is_list(data[:tabs]) and data[:tabs] != [] -> tab_runs(data[:tabs])
        is_binary(data[:title]) -> [{data[:title], title_style}]
        true -> []
      end

    digit = if is_integer(data[:digit]), do: [{"#{data[:digit]} ", :label}], else: []

    case digit ++ body do
      [] -> []
      runs -> [{" ", :normal} | runs] ++ [{" ", :normal}]
    end
  end

  defp tab_runs(tabs) do
    tabs
    |> Enum.map(fn {label, active?} -> {label, if(active?, do: :header, else: :dim)} end)
    |> Enum.intersperse({" · ", :dim})
  end

  defp hint_runs(%{hint: hint}) when is_binary(hint), do: [{" ", :normal}, {hint, :dim}, {" ", :normal}]
  defp hint_runs(_data), do: []

  defp box(%{w: w, h: h} = rect, style, {tl, tr, bl, br, horiz, vert}, label, hint) when w >= 2 and h >= 2 do
    inner = w - 2
    top = frame_row(tl, tr, horiz, inner, style, label, 1)
    bottom = frame_row(bl, br, horiz, inner, style, hint, max(inner - Panel.row_width(hint) - 1, 0))
    side = [{vert, style}, {String.duplicate(" ", inner), :normal}, {vert, style}]

    Panel.clip([top] ++ List.duplicate(side, h - 2) ++ [bottom], rect)
  end

  defp box(_rect, _style, _glyphs, _label, _hint), do: []

  # A frame row: corners + rule, with `overlay` punched in at rule offset `at`. An overlay that
  # doesn't fit is dropped whole (clipping it would eat the corner).
  defp frame_row(left, right, horiz, inner, style, [], _at),
    do: [{left <> String.duplicate(horiz, inner) <> right, style}]

  defp frame_row(left, right, horiz, inner, style, overlay, at) do
    ow = Panel.row_width(overlay)

    if ow + at > inner do
      frame_row(left, right, horiz, inner, style, [], at)
    else
      [{left <> String.duplicate(horiz, at), style}] ++
        overlay ++ [{String.duplicate(horiz, inner - at - ow) <> right, style}]
    end
  end
end
```

**Step 4: Run tests**

Run: `mise exec -- mix test test/aleph/panel/border_test.exs`
Expected: PASS. Also run `mise exec -- mix test test/aleph/view_test.exs` — must still pass
(View still sends `%{focused: true}` / `nil`; both shapes render).

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/panel/border.ex modules/aleph/test/aleph/panel/border_test.exs
git commit -F - <<'EOF'
aleph: border frames carry title/digit/tabs/hint (cockpit clarity slice 1)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
```

### Task 1.2: View passes section identity + digits to every border

**Files:**
- Modify: `modules/aleph/lib/aleph/view.ex`
- Test: `modules/aleph/test/aleph/view_test.exs`

**Step 1: Write the failing tests** (append a describe block to `view_test.exs`):

```elixir
  describe "border titles + digits (clarity slice 1)" do
    defp border_of(placements, title) do
      Enum.find_value(placements, fn
        {Panel.Border, %{title: ^title} = data, _rect} -> data
        _ -> nil
      end)
    end

    test "world sidebar boxes carry digit-first titles derived from layout order" do
      placements = View.compose(reads(%{}), 120, 40)

      assert %{digit: 1} = border_of(placements, "SPACES")
      assert %{digit: 2} = border_of(placements, "STACK")
      assert %{digit: 3} = border_of(placements, "MEMORY")
      assert %{digit: 4} = border_of(placements, "HEALTH")
    end

    test "the center terminal box carries digit 0 and no title" do
      placements = View.compose(reads(%{}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border, %{digit: 0, title: nil}, _rect} -> true
               _ -> false
             end)
    end

    test "orbis boxes are titled too (shared pieces inherit)" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      assert border_of(placements, "IN FLIGHT")
      assert border_of(placements, "IN SCOPE")
    end
  end
```

Note: `reads(%{})` uses `active_key: 0` — the hardcoded Tlön fallback World (funes isn't up
under test), whose right column is `[Health, Crew, Activity, Leaves]`. Until Task 2.2 the
right column still renders ONE panel (`right_pane_view` 0 → Health), so only HEALTH is
asserted on the right here.

**Step 2: Run to verify failure**

Run: `mise exec -- mix test test/aleph/view_test.exs`
Expected: FAIL (`border_of` finds nothing — border data has no `:title`).

**Step 3: Implement in `view.ex`**

3a. In `compose/3`, replace the `columns`/`boxes`/`borders`/`contents` section
(lines ~65–96) with digit-aware assembly:

```elixir
    left_sections = [Panel.Spaces | space.left]
    right_sections = right_panels(space, reads)

    columns =
      case layout_for(w) do
        :wide ->
          %{left: left, center: center, right: right} = wide_columns(w, body_h)

          [
            {left, left_sections, 1},
            {center, center_panels, :center},
            {right, right_sections, 1 + length(left_sections)}
          ]

        :narrow ->
          sections = left_sections ++ center_panels ++ right_sections
          [{%{x: 0, y: 0, w: w, h: body_h}, sections, 1}]
      end

    boxes =
      Enum.flat_map(columns, fn {rect, panels, digits} ->
        panels |> boxed(rect) |> assign_digits(digits)
      end)

    focused = focused_section(reads[:focus], space)

    borders =
      Enum.map(boxes, fn {section, rect, digit} ->
        {Panel.Border, border_data(section, digit, focused), rect}
      end)

    slice = focus_slice(reads)

    contents =
      Enum.map(boxes, fn {section, rect, _digit} ->
        content_for(section, reads, inset(rect), if(section == focused, do: slice))
      end)
```

3b. Add the digit/title helpers (near `border_data`; delete the old 2-arity `border_data`):

```elixir
  # Sidebar boxes number top-down from `start` (left 1.., right continuing); the center's
  # terminal box alone is 0 — Alt+0/`0` mean "back to the terminal" (design 2026-08-23).
  defp assign_digits(boxes, :center),
    do: Enum.map(boxes, fn {section, rect} -> {section, rect, if(terminal_section?({section, rect}), do: 0)} end)

  defp assign_digits(boxes, start) do
    boxes
    |> Enum.with_index(start)
    |> Enum.map(fn {{section, rect}, d} -> {section, rect, d} end)
  end

  defp border_data(section, digit, focused) do
    %{
      focused: not is_nil(focused) and section == focused,
      digit: digit,
      title: section_title(section)
    }
  end

  # The on-frame title per section. A section with no entry (Terminal, WindowBar, Pulse, the
  # center surfaces) gets a bare frame.
  defp section_title({panel, _read_key}), do: section_title(panel)
  defp section_title(Panel.Spaces), do: "SPACES"
  defp section_title(Panel.Stack), do: "STACK"
  defp section_title(Panel.Memory), do: "MEMORY"
  defp section_title(Panel.Health), do: "HEALTH"
  defp section_title(Panel.Crew), do: "CREW"
  defp section_title(Panel.Activity), do: "ACTIVITY"
  defp section_title(Panel.Leaves), do: "LEAVES"
  defp section_title(Panel.Roster), do: "IN FLIGHT"
  defp section_title(Panel.Triage), do: "TRIAGE"
  defp section_title(Panel.Dossier), do: "IN SCOPE"
  defp section_title(_section), do: nil
```

Add the missing aliases at the top if not present (`Panel.Roster` etc. are reached via the
`Panel.` prefix — `alias Aleph.Panel` already covers them).

**Step 4: Run tests**

Run: `mise exec -- mix test test/aleph/view_test.exs`
Expected: PASS, including the pre-existing focus-highlight tests (border data is now always a
map; the `%{focused: true}` matches still hold).

**Step 5: Commit** (same `-F` + trailer discipline; message:
`aleph: view numbers + titles every section border`).

### Task 1.3: Delete the in-content header rows; fix pick math

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/{spaces,stack,memory,health,crew,activity,leaves,roster,triage,dossier}.ex`
- Modify: `modules/aleph/lib/aleph/view.ex` (`fixed_height(Panel.Spaces)`)
- Tests: the matching `test/aleph/panel/*_test.exs` files

For each panel, delete the leading `line("TITLE", :header), blank()` (the title now lives on
the frame), keeping any *content* the header carried. Specifics:

1. **Spaces** (`spaces.ex`): `header = []` — delete the `header` binding and render
   `Panel.clip(body, rect)`. **pick/3 changes** (rows now start at 0):
   ```elixir
   @impl Aleph.Panel
   def pick(%{spaces: spaces}, _rect, local_y) do
     spaces |> Enum.at(local_y) |> switch_space()
   end
   ```
   (Drop the `Aleph.Panel.item_at/2` call. `Enum.at/2` with an out-of-range or negative-ish
   index returns nil → `switch_space(nil)` → nil, same as before.)
2. **Stack**: delete `header = [line("STACK", :header), blank()]`; `rows = branch_section ++ …`.
3. **Memory**: delete the `line("MEMORY", :header)` lead run in BOTH render clauses. The nil
   clause becomes `Panel.clip([line("no recall yet", :dim)], rect)`. Coverage stays first.
4. **Health**: `header = []` → render `Panel.clip(rows(data), rect)`.
5. **Crew**: the header carried the leaves count — keep it as content:
   ```elixir
   header = [[{"leaves #{live}/#{cap}", :dim}], blank()]
   ```
6. **Activity**: delete `line("funes · activity", :header), blank()`.
7. **Leaves**: header `[title, blank, summary, blank]` → `[summary_row(summary), blank()]`;
   change `@header_rows 4` → `@header_rows 2` (pick math). The nil clause →
   `Panel.clip([line("no machine threads", :dim)], rect)`.
8. **Roster / Triage / Dossier**: delete their `line(.., :header), blank()` leads (Roster
   "IN FLIGHT", Triage "TRIAGE", Dossier "IN SCOPE"; Triage/Dossier placeholder clauses lose
   the header too). **Roster.pick** uses `Panel.item_at/2` (2 chrome rows) — replace with
   `Enum.at(roster, Aleph.Panel.scroll_offset(data) + local_y)` (same nil-tolerant shape as
   Spaces). Leave `ThreadList`, `Logbook`, `Habits`, `Settings` untouched (not placed by any
   current space).

Then in `view.ex`: `defp fixed_height(Panel.Spaces), do: length(Space.all()) + 2` (rows + the
2 frame rows — the 2 header rows are gone).

**TDD order:** for each panel, first update its test to assert the FIRST row is content (not
the old header), run to see it fail, then edit the panel. E.g. in `panel/stack_test.exs`
change assertions like `assert [first | _] = rows; assert {"STACK", :header} in first` to
assert the branch row leads. In `panel/leaves_test.exs` the pick tests shift by 2 rows.

Check for stragglers when done:

```bash
grep -rn '"STACK"\|"MEMORY"\|"HEALTH"\|"CREW"\|"LEAVES"\|"SPACES"\|"IN FLIGHT"\|"TRIAGE"\|"IN SCOPE"\|funes · activity' modules/aleph/lib/aleph/panel/ modules/aleph/test/
```

(Remaining hits should be border titles in `view.ex`, tests, and unrelated strings only.)

**Run:** `mise exec -- mix test` — cockpit tests (`cockpit_*.exs`) may assert on old row
positions; fix any that depended on header rows.

**Commit:** `aleph: section titles move to the frame — in-content headers die`.

### Task 1.4: Memory's empty HABITS collapses; section count follows

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/memory.ex`
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (`tlon_layout/1` sections)
- Tests: `test/aleph/panel/memory_test.exs`, `test/aleph/keymap_test.exs` (only if it pins
  Memory's section count)

**Step 1: Failing test** (memory_test.exs):

```elixir
  test "an empty HABITS section collapses to nothing — no label, no dash" do
    data = %{coverage: nil, floor: [%{text: "a fact"}], habits: []}
    rows = Aleph.Panel.Memory.render(data, %{x: 0, y: 0, w: 40, h: 20})
    texts = Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

    refute Enum.any?(texts, &String.contains?(&1, "HABITS"))
    # no trailing blank+placeholder either: the floor takes the space
    refute List.last(texts) == "  —"
  end
```

**Step 2:** run `mise exec -- mix test test/aleph/panel/memory_test.exs` → FAIL.

**Step 3:** in `memory.ex`, change the row assembly:

```elixir
    rows =
      coverage_rows(Map.get(data, :coverage)) ++
        [rule(rect.w)] ++
        floor_rows(floor, section == @floor_section, selected, rect.w) ++
        habit_block(habits, section == @habits_section, selected, rect.w)
```

and add:

```elixir
  # Empty HABITS collapses to nothing (design 2026-08-23): FLOOR takes the space, and the
  # cockpit's section count drops to 1 so Tab can't land on a section that isn't drawn.
  defp habit_block([], _active?, _selected, _w), do: []
  defp habit_block(habits, active?, selected, w), do: [blank() | habit_rows(habits, active?, selected, w)]
```

(`habit_rows/4` keeps its non-empty body; its `[] -> [line("  —", :dim)]` branch is now dead —
delete it.)

**Step 4:** in `cockpit.ex` `tlon_layout/1`, replace `sections: %{Panel.Memory => 2}` with
`sections: %{Panel.Memory => memory_sections(state)}` and add nearby:

```elixir
  # HABITS collapses when empty (Panel.Memory), so the Tab ring must shrink with it.
  defp memory_sections(%{memory: %{habits: habits}}) when habits != [], do: 2
  defp memory_sections(_state), do: 1
```

**Step 5:** `mise exec -- mix test` → PASS. Then the slice gate:

```bash
mise run aleph:check
```

**Commit:** `aleph: empty HABITS collapses; memory section ring follows`.

---

# Slice 2 — Right column reshape: Health pinned + tabbed carousel (CREW default)

Outcome: right column = `4 HEALTH` at intrinsic height, then ONE carousel panel at full
remaining height whose border title is a clickable tab strip `5 CREW · ACTIVITY · LEAVES`.
Default view CREW. `[`/`]` still cycles; clicking a tab switches.

### Task 2.1: `Space.visible_right/2` + `Space.carousel/1` (single source for View, keymap, cockpit)

**Files:**
- Modify: `modules/aleph/lib/aleph/space.ex`
- Test: `modules/aleph/test/aleph/space_test.exs`

**Step 1: Failing tests** (space_test.exs):

```elixir
  describe "visible_right/2 (clarity slice 2)" do
    test "world right column = pinned Health + the view-indexed carousel panel, CREW at 0" do
      space = Aleph.Space.first_world()
      assert Aleph.Space.carousel(space) == [Aleph.Panel.Crew, Aleph.Panel.Activity, Aleph.Panel.Leaves]
      assert Aleph.Space.visible_right(space, 0) == [Aleph.Panel.Health, Aleph.Panel.Crew]
      assert Aleph.Space.visible_right(space, 2) == [Aleph.Panel.Health, Aleph.Panel.Leaves]
      assert Aleph.Space.visible_right(space, 3) == [Aleph.Panel.Health, Aleph.Panel.Crew]
    end

    test "a single-panel right column (Orbis) is just the pinned panel" do
      [orbis | _] = Aleph.Space.all([])
      assert Aleph.Space.visible_right(orbis, 5) == [Aleph.Panel.Dossier]
      assert Aleph.Space.carousel(orbis) == []
    end
  end
```

**Step 2:** run → FAIL (undefined functions).

**Step 3:** add to `space.ex`:

```elixir
  @doc """
  The right column actually on screen (design 2026-08-23): the FIRST right panel pinned
  (HEALTH), plus the `view`-indexed one of the rest — the carousel, CREW default at index 0.
  Also the exact shape the Focus SM navigates, so View/keymap/cockpit can never disagree.
  """
  @spec visible_right(t(), non_neg_integer()) :: [module() | {module(), atom()}]
  def visible_right(%__MODULE__{right: []}, _view), do: []
  def visible_right(%__MODULE__{right: [pinned]}, _view), do: [pinned]

  def visible_right(%__MODULE__{right: [pinned | carousel]}, view),
    do: [pinned, Enum.at(carousel, rem(view, length(carousel)))]

  @doc "The carousel members (everything after the pinned head) — the tab strip's panels."
  @spec carousel(t()) :: [module() | {module(), atom()}]
  def carousel(%__MODULE__{right: [_pinned | rest]}), do: rest
  def carousel(_space), do: []
```

**Step 4:** run → PASS. **Commit:** `aleph: Space.visible_right/carousel — the right-column contract`.

### Task 2.2: View renders pinned Health + carousel with tab-strip border

**Files:**
- Modify: `modules/aleph/lib/aleph/view.ex`
- Test: `modules/aleph/test/aleph/view_test.exs`

**Step 1: Failing tests:**

```elixir
  describe "right column: pinned Health + carousel (clarity slice 2)" do
    defp health_data,
      do: %{version: nil, funes_up: true, tlon_up: true, nix_gen: 1, nix_behind: 0,
            disk_pct: 10, mem_pct: 10, load_avg: 0.1, tools: []}

    test "CREW is the default carousel view, below a pinned HEALTH" do
      placements = View.compose(reads(%{health: health_data()}), 120, 40)

      assert {_p, _d, health_rect} = Enum.find(placements, &match?({Panel.Health, _, _}, &1))
      assert {_p, _d, crew_rect} = Enum.find(placements, &match?({Panel.Crew, _, _}, &1))
      refute Enum.any?(placements, &match?({Panel.Activity, _, _}, &1))
      assert crew_rect.y > health_rect.y
      # pinned: Health's box hugs its content instead of splitting the column evenly
      assert health_rect.h < crew_rect.h
    end

    test "right_pane_view picks the carousel panel" do
      placements = View.compose(reads(%{health: health_data(), right_pane_view: 1}), 120, 40)
      assert Enum.any?(placements, &match?({Panel.Activity, _, _}, &1))
      refute Enum.any?(placements, &match?({Panel.Crew, _, _}, &1))
    end

    test "the carousel border is a tab strip with the active tab, digit 5" do
      placements = View.compose(reads(%{health: health_data()}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border, %{digit: 5, tabs: [{"CREW", true}, {"ACTIVITY", false}, {"LEAVES", false}]}, _r} -> true
               _ -> false
             end)
    end
  end
```

**Step 2:** run → FAIL.

**Step 3: Implement in `view.ex`:**

3a. Replace `right_panels/2` with `Space.visible_right/2` and give the right column its own
pinning-aware box builder. In `compose/3`:

```elixir
    right_sections = Space.visible_right(space, reads[:right_pane_view] || 0)
```

then drop the generic `columns` list from Task 1.2 in favor of explicit per-column assembly
(the right column is no longer a plain `boxed/2` stack):

```elixir
    boxes =
      case layout_for(w) do
        :wide ->
          %{left: left, center: center, right: right} = wide_columns(w, body_h)

          assign_digits(boxed(left_sections, left), 1) ++
            assign_digits(boxed(center_panels, center), :center) ++
            assign_digits(pinned_boxes(right_sections, right, reads), 1 + length(left_sections))

        :narrow ->
          sections = left_sections ++ center_panels ++ right_sections
          assign_digits(boxed(sections, %{x: 0, y: 0, w: w, h: body_h}), 1)
      end
```

`compose/3` continues from `boxes` exactly as in Task 1.2. Then add:

```elixir
  # The right column (design 2026-08-23): the pinned head at intrinsic height (content + 2
  # frame rows, never flexed), the carousel below at full remaining height.
  defp pinned_boxes([], _rect, _reads), do: []
  defp pinned_boxes([only], rect, _reads), do: boxed([only], rect)

  defp pinned_boxes([pinned, carousel_panel], %{x: x, y: y, w: w, h: h}, reads) do
    pinned_h = min(intrinsic_height(pinned, reads, w) + 2, h)
    rest_h = max(h - pinned_h - @gap, 0)

    [
      {pinned, %{x: x, y: y, w: w, h: pinned_h}},
      {carousel_panel, %{x: x, y: y + pinned_h + @gap, w: w, h: rest_h}}
    ]
  end

  # Content height at the box's inset width. nil data (probe not run yet — pure tests, boot
  # frame) gets a stable nominal so the layout doesn't jump when the probe lands ≈ its size.
  defp intrinsic_height(section, reads, box_w) do
    {panel, data, _rect} = content_for(section, reads, %{x: 0, y: 0, w: max(box_w - 4, 1), h: 1})
    if data == nil, do: 10, else: Panel.content_height(panel, data, max(box_w - 4, 1))
  end
```

3b. Carousel tabs on the border. `border_data/3` grows a `reads`+`space` context — change the
border assembly to close over them:

```elixir
    carousel_active = List.last(right_sections)

    borders =
      Enum.map(boxes, fn {section, rect, digit} ->
        {Panel.Border, border_data(section, digit, focused, carousel_border(space, reads, section, carousel_active)), rect}
      end)
```

Simplest concrete shape — make `border_data/4`:

```elixir
  defp border_data(section, digit, focused, tabs) do
    %{
      focused: not is_nil(focused) and section == focused,
      digit: digit,
      title: if(tabs, do: nil, else: section_title(section)),
      tabs: tabs
    }
  end

  # The carousel box's tab strip: every carousel member's title, the visible one lit. nil for
  # every other box (and when there's no carousel — Orbis).
  defp carousel_border(space, reads, section, carousel_active) do
    carousel = Space.carousel(space)

    if carousel != [] and section == carousel_active and section in carousel do
      active = Enum.at(carousel, rem(reads[:right_pane_view] || 0, length(carousel)))
      Enum.map(carousel, fn p -> {section_title(p), p == active} end)
    end
  end
```

Guard the degenerate case where the active carousel panel also appears in the left column
(it can't today — panel modules are unique per space — so `section == carousel_active` is
sufficient; note it and move on).

**Step 4:** run `mise exec -- mix test test/aleph/view_test.exs` → PASS. Full
`mise exec -- mix test` — `center_rect/3` and older view tests must still pass (center math
untouched).

**Step 5: Commit:** `aleph: right column = pinned HEALTH + tabbed carousel, CREW default`.

### Task 2.3: Cockpit — cycle wraps the carousel; focus layout matches; tab click switches

**Files:**
- Modify: `modules/aleph/lib/aleph/cockpit.ex`
- Test: `modules/aleph/test/aleph/cockpit_test.exs` (or the most fitting existing cockpit test
  file — `cycle_pane_view` tests live where the C3.4 tests are; find with
  `grep -rn cycle_pane_view modules/aleph/test/`)

**Step 1: Failing tests** (pure — `cycle_pane_view/2` is public):

```elixir
  test "cycle_pane_view wraps the CAROUSEL (Health excluded): 0→1→2→0" do
    state = %{active_key: 0, right_pane_view: 0}
    assert Aleph.Cockpit.cycle_pane_view(state, 1).right_pane_view == 1
    assert Aleph.Cockpit.cycle_pane_view(%{state | right_pane_view: 2}, 1).right_pane_view == 0
    assert Aleph.Cockpit.cycle_pane_view(state, -1).right_pane_view == 2
  end
```

**Step 2:** run → FAIL (today it wraps at 4, so `right_pane_view: 2` + 1 → 3).

**Step 3: Implement:**

3a. `cycle_pane_view/2`:

```elixir
  def cycle_pane_view(%{active_key: key} = state, dir) when Space.world?(key) do
    case Space.fetch(key) do
      %Space{} = space ->
        case Space.carousel(space) do
          [] -> state
          carousel ->
            n = length(carousel)
            %{state | right_pane_view: rem(state.right_pane_view + dir + n, n)}
        end

      nil ->
        state
    end
  end
```

3b. `tlon_layout/1` — the focus SM must navigate what's on screen, not the full right list:

```elixir
        %{
          left: [Panel.Spaces | space.left],
          right: Space.visible_right(space, state.right_pane_view),
          sections: %{Panel.Memory => memory_sections(state)},
          counts: pane_counts(state)
        }
```

(`state.right_pane_view` is always present in cockpit state; keymap tests that build literal
layouts are unaffected.)

3c. Tab click. In the `:left`-press `handle_cast` (~line 413), route border-tab hits first:

```elixir
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left, action: :press}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}

    case border_tab_hit(state.placements, x, y) do
      nil -> dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, state)
      idx -> {:noreply, render(%{state | right_pane_view: idx})}
    end
  end
```

and add near the other mouse helpers:

```elixir
  # A press on the carousel box's top frame row: which tab (Border.tab_at_x mirrors the drawn
  # runs)? Borders are chrome to hit_panel, so this runs before it.
  defp border_tab_hit(placements, x, y) do
    Enum.find_value(placements, fn
      {Panel.Border, %{tabs: tabs} = data, rect} when is_list(tabs) ->
        if y == rect.y and x >= rect.x and x < rect.x + rect.w, do: Panel.Border.tab_at_x(data, x - rect.x)

      _placement ->
        nil
    end)
  end
```

**Step 4:** `mise exec -- mix test` → PASS. Any keymap/cockpit test that asserted the old
4-wide wrap or `sections: %{Panel.Memory => 2}` gets updated to the new truth.

**Step 5:** slice gate `mise run aleph:check`, then commit:
`aleph: carousel cycle wraps CREW/ACTIVITY/LEAVES; tab click switches`.

---

# Slice 3 — Contextual footer via `Panel.hints/1`

Outcome: the footer's hints line = mode segment + space segment + focused-pane segment,
assembled from data. The stale label-keyed table (`hints_for("Tlön", …)`) dies. Panels declare
their verbs.

### Task 3.1: The `hints/1` callback + panel implementations

**Files:**
- Modify: `modules/aleph/lib/aleph/panel.ex`
- Modify: `modules/aleph/lib/aleph/panel/{stack,memory,leaves,spaces}.ex`
- Test: `modules/aleph/test/aleph/panel/stack_test.exs` (plus one line each in memory/leaves/spaces tests)

**Step 1: Failing test (stack_test.exs):**

```elixir
  test "hints/1 declares the pane's footer verbs" do
    assert Aleph.Panel.hints(Aleph.Panel.Stack, %{}) == [{"j/k", "commits"}, {"⏎", "diff"}, {"y", "sha"}]
  end

  test "a panel without hints/1 declares nothing" do
    assert Aleph.Panel.hints(Aleph.Panel.Health, %{}) == []
  end
```

**Step 2:** run → FAIL (`Aleph.Panel.hints/2` undefined).

**Step 3:** in `panel.ex` add the callback + dispatcher:

```elixir
  @doc "The pane's footer verbs as `{keycap, label}` pairs — the contextual footer's third segment."
  @callback hints(data :: term()) :: [{String.t(), String.t()}]

  @optional_callbacks [pick: 3, hints: 1]

  @doc "A panel's declared footer verbs, or [] — `hints/1` is optional."
  @spec hints(module(), term()) :: [{String.t(), String.t()}]
  def hints(panel, data) do
    if function_exported?(panel, :hints, 1), do: panel.hints(data) || [], else: []
  end
```

Implementations (each next to the panel's `pick/3` or at the bottom):

```elixir
# stack.ex
  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "commits"}, {"⏎", "diff"}, {"y", "sha"}]

# memory.ex — NOTE: section-cycle is `s` since the C3.4 reshuffle (Tab switches spaces);
# the design doc's "Tab section" example predates that — the footer must tell the truth.
  @impl Aleph.Panel
  def hints(_data), do: [{"s", "section"}, {"j/k", "facts"}, {"⏎", "open"}]

# leaves.ex
  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "leaves"}, {"⏎", "attach"}]

# spaces.ex
  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "spaces"}, {"⏎", "switch"}]
```

**Step 4:** run → PASS. **Commit:** `aleph: Panel.hints/1 — panes declare their footer verbs`.

### Task 3.2: StatusBar assembles the three segments; stale table dies

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/status_bar.ex`
- Modify: `modules/aleph/lib/aleph/style.ex` (add `stat_warn`)
- Test: `modules/aleph/test/aleph/panel/` — create `status_bar_test.exs` if none exists
  (check: `ls modules/aleph/test/aleph/panel/ | grep status`); otherwise extend.

**Step 1: Failing tests:**

```elixir
defmodule Aleph.Panel.StatusBarTest do
  use ExUnit.Case, async: true

  alias Aleph.Panel.StatusBar

  defp rect, do: %{x: 0, y: 0, w: 120, h: 2}
  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

  defp base(over) do
    Map.merge(
      %{space: "Tlön", thread: nil, thread_count: 0, live_count: 0, input: nil, flash: nil,
        leader_pending?: false, focus: nil, mode: nil, world?: false, lock?: false, pane_hints: []},
      over
    )
  end

  test "TERM mode: the mode segment names the Alt door and the nav toggle" do
    [_info, hints] = StatusBar.render(base(%{mode: :term, world?: true}), rect())
    line = hints |> Enum.map_join(fn {t, _} -> t end)
    assert line =~ "Alt+#"
    assert line =~ "^␣"
    refute line =~ "space"
  end

  test "NAV mode: mode + space verbs + the focused pane's own verbs" do
    data = base(%{mode: :nav, world?: true, pane_hints: [{"j/k", "commits"}, {"⏎", "diff"}]})
    [_info, hints] = StatusBar.render(data, rect())
    line = hints |> Enum.map_join(fn {t, _} -> t end)
    assert line =~ "Alt+0"
    assert line =~ "c post"
    assert line =~ "n task"
    assert line =~ "m driver"
    assert line =~ "j/k commits"
    assert line =~ "⏎ diff"
  end

  test "LOCK mode: the unlock chord alone, and a warning chip" do
    [info, hints] = StatusBar.render(base(%{mode: :lock, world?: true}), rect())
    assert {" LOCK ", :stat_warn} in info
    line = hints |> Enum.map_join(fn {t, _} -> t end)
    assert line =~ "Alt+g unlock"
    refute line =~ "post"
  end

  test "a non-world space (mode nil) keeps the shared leader table" do
    [_info, hints] = StatusBar.render(base(%{space: "Orbis"}), rect())
    assert hints |> Enum.map_join(fn {t, _} -> t end) =~ "^␣n new"
  end

  test "hints keyed on world-ness, never the label: a renamed world still gets world hints" do
    data = base(%{space: "Uqbar", mode: :nav, world?: true})
    [_info, hints] = StatusBar.render(data, rect())
    assert hints |> Enum.map_join(fn {t, _} -> t end) =~ "c post"
  end
end
```

**Step 2:** run → FAIL.

**Step 3: Implement in `status_bar.ex`.** The modal clauses (`:compose`, `:new_thread`,
`:new_world`, `:new_path`, `:new_roster`, `flash`, `leader_pending?`) stay verbatim. Replace
the default clause's hint plumbing:

```elixir
  @impl Panel
  def render(%{space: space} = data, rect) do
    thread = data[:thread] || "—"
    threads = data[:thread_count] || 0
    live = data[:live_count] || 0

    left =
      mode_chip(data) ++
        [{" #{space} ", :tab}, {"  ", :normal}, {"▸ ", :accent}, {thread, :normal}]

    right = [{" ◷ #{threads} threads ", :stat}, {" ", :normal}, {" ● #{live} live ", :stat_live}]

    Panel.clip([justify(left, right, rect.w), hints_row(assemble_hints(data))], rect)
  end

  # LOCK outranks TERM/NAV — total passthrough deserves the loudest chip.
  defp mode_chip(%{mode: :lock}), do: [{" LOCK ", :stat_warn}, {" ", :normal}]
  defp mode_chip(%{focus: %{in_terminal?: true}}), do: [{" TERM ", :stat_live}, {" ", :normal}]
  defp mode_chip(%{focus: %{in_terminal?: false}}), do: [{" NAV ", :stat}, {" ", :normal}]
  defp mode_chip(_data), do: []

  # The contextual footer (design 2026-08-23): mode → space → pane, mode-first because clip/2
  # trims from the right — pane verbs drop first on a narrow frame, the mode chip survives.
  # Keyed on world-ness (mode/world? from View.status_data), NEVER the space label.
  defp assemble_hints(%{mode: nil}), do: @hints
  defp assemble_hints(data), do: mode_seg(data.mode) ++ space_seg(data) ++ (data[:pane_hints] || [])

  defp mode_seg(:term), do: [{"Alt+#", "panes"}, {"^␣", "nav"}]
  defp mode_seg(:nav), do: [{"Alt+0", "term"}, {"q", "quit"}]
  defp mode_seg(:lock), do: [{"Alt+g", "unlock"}]

  defp space_seg(%{mode: :nav, world?: true}), do: [{"c", "post"}, {"n", "task"}, {"m", "driver"}]
  defp space_seg(_data), do: []
```

Delete: the old `mode_chip/1` focus-arg clauses, `hints_for/1`, `hints_for/2` (all the
`"Tlön"`-keyed clauses). Keep `@hints`, `@leader_hints`, `hints_row/0`, `hints_row/1`,
`cursor_split/1`, `justify/3`.

In `style.ex` add to `@colors` next to the other chips:

```elixir
    stat_warn: {@ink, 0xFF5555},
```

**Step 4:** run the new test file → PASS.

### Task 3.3: View feeds mode/world?/pane_hints into the footer

**Files:**
- Modify: `modules/aleph/lib/aleph/view.ex`
- Test: `modules/aleph/test/aleph/view_test.exs`

**Step 1: Failing tests:**

```elixir
  describe "contextual footer data (clarity slice 3)" do
    defp status_of(placements),
      do: Enum.find_value(placements, fn
            {Panel.StatusBar, data, _rect} -> data
            _ -> nil
          end)

    test "world + nav: mode :nav, world? true, and the focused pane's hints (carousel appends [/])" do
      focus = %Focus{in_terminal?: false, column: :right, pane: 1}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))

      assert data.mode == :nav
      assert data.world? == true
      # right pane 1 is the carousel slot (CREW by default — no verbs of its own) → just [/]
      assert {"[/]", "view"} in data.pane_hints
    end

    test "world + terminal: mode :term, no pane hints" do
      data = status_of(View.compose(reads(%{focus: Focus.new()}), 120, 40))
      assert data.mode == :term
      assert data.pane_hints == []
    end

    test "orbis: mode nil (the shared table)" do
      data = status_of(View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40))
      assert data.mode == nil
      assert data.world? == false
    end

    test "a focused Stack pane's own verbs ride through" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 1}
      data = status_of(View.compose(reads(%{focus: focus}), 120, 40))
      assert {"⏎", "diff"} in data.pane_hints
    end
  end
```

**Step 2:** run → FAIL.

**Step 3:** in `view.ex`, change the status placement to pass the focused section
(`status_data(reads, space, focused)`) and extend:

```elixir
  defp status_data(reads, space, focused) do
    %{
      space: space.label,
      thread: reads.focused_title,
      thread_count: length(reads.threads),
      live_count: Enum.count(reads.roster, & &1.warm?),
      input: reads[:input],
      flash: reads[:flash],
      leader_pending?: reads[:leader_pending?],
      focus: reads[:focus],
      # The contextual footer's keys (design 2026-08-23) — world-ness, never the label.
      mode: footer_mode(reads),
      world?: Space.world?(space.key),
      lock?: reads[:lock?] == true,
      pane_hints: pane_hints(reads, space, focused)
    }
  end

  defp footer_mode(%{lock?: true}), do: :lock
  defp footer_mode(%{focus: %Focus{in_terminal?: true}}), do: :term
  defp footer_mode(%{focus: %Focus{}}), do: :nav
  defp footer_mode(_reads), do: nil

  # The focused pane's declared verbs; the carousel slot appends the view-cycle key.
  defp pane_hints(_reads, _space, nil), do: []

  defp pane_hints(reads, space, focused) do
    {panel, data, _rect} = content_for(focused, reads, %{x: 0, y: 0, w: 40, h: 10})
    hints = Panel.hints(panel, data)
    if focused in Space.carousel(space), do: hints ++ [{"[/]", "view"}], else: hints
  end
```

(`require Aleph.Space` is already in scope? Check — View aliases `Aleph.Space`; add
`require Space` at the top since `world?/1` is a defguard used in an expression: defguards are
callable in any expression context but still need the `require`.)

**Step 4:** run `mise exec -- mix test` → PASS (older tests composing reads without `:lock?`
still work — `footer_mode` pattern-matches on key presence). Slice gate `mise run aleph:check`.

**Step 5: Commit:** `aleph: contextual footer — mode/space/pane segments, stale table dies`.

---

# Slice 4 — Global Alt chords + LOCK mode

Outcome: `Alt+1..9` jump panes from anywhere (implicit NAV), `Alt+0` → terminal, `Alt+h/j/k/l`
move panes, `Alt+n/c/[/]` fire verbs, `Alt+g` toggles LOCK (total passthrough). Bare digits in
NAV are the no-plumbing fallback (`^␣ 5`).

**RISK (from the design):** Alt must reach the keymap as `%{key: :char, char: c, alt: true}`.
Under the Kitty CSI-u disambiguate mode the cockpit already arms (`\e[>1u`), kitty sends
Alt+h as `\e[104;3u`, and the patched raxol `InputParser` (see `mix.exs`
`ensure_raxol_kitty_parser/1` — `mods_to_opts` decodes the alt bit) turns that into exactly
that shape. **Verify live in kitty before trusting** (Task 4.5); slices 1–3 don't depend on
this slice, and bare-digit-in-NAV works regardless.

### Task 4.1: `Focus.jump/3` — digit → pane, matching the View numbering

**Files:**
- Modify: `modules/aleph/lib/aleph/tlon/focus.ex`
- Test: `modules/aleph/test/aleph/tlon/focus_test.exs`

**Step 1: Failing tests:**

```elixir
  describe "jump/3 (Alt+digit)" do
    # Numbering contract (design 2026-08-23): 0 = terminal; left column 1..n top-down; right
    # column continues. Must match Aleph.View's border digits — pinned by a view_test.
    defp jump_layout,
      do: %{left: [:spaces, :stack, :memory], right: [:health, :crew], sections: %{}, counts: %{}}

    test "0 enters the terminal from nav" do
      s = %Focus{in_terminal?: false, column: :left, pane: 2}
      assert Focus.jump(s, jump_layout(), 0).in_terminal? == true
    end

    test "a left digit lands on that pane, implicit nav, section reset" do
      s = %Focus{in_terminal?: true, section: 1}
      j = Focus.jump(s, jump_layout(), 2)
      assert %{in_terminal?: false, column: :left, pane: 1, section: 0} = Map.take(j, [:in_terminal?, :column, :pane, :section])
    end

    test "a right digit continues past the left column" do
      j = Focus.jump(%Focus{}, jump_layout(), 5)
      assert %{in_terminal?: false, column: :right, pane: 1} = Map.take(j, [:in_terminal?, :column, :pane])
    end

    test "a digit past the last pane is a no-op" do
      s = %Focus{}
      assert Focus.jump(s, jump_layout(), 9) == s
    end
  end
```

**Step 2:** run → FAIL. **Step 3:** add to `focus.ex`:

```elixir
  @doc """
  Jump straight to pane number `digit` (the border-title numbers): 0 = the terminal, left
  column 1..n top-down, right column continuing — implicit nav, section reset. Out-of-range
  digits no-op. Works FROM the terminal too (unlike nav intents) — that's the point.
  """
  @spec jump(t(), map(), non_neg_integer()) :: t()
  def jump(%__MODULE__{} = s, _layout, 0), do: %{s | in_terminal?: true}

  def jump(%__MODULE__{} = s, layout, digit) do
    left = column(layout, :left)
    right = column(layout, :right)

    cond do
      digit <= length(left) ->
        %{s | in_terminal?: false, column: :left, pane: digit - 1, section: 0}

      digit <= length(left) + length(right) ->
        %{s | in_terminal?: false, column: :right, pane: digit - 1 - length(left), section: 0}

      true ->
        s
    end
  end
```

**Step 4:** run → PASS. **Commit:** `aleph: Focus.jump/3 — digit-addressed panes`.

### Task 4.2: Keymap — LOCK mode + global Alt chords + bare-digit NAV fallback

**Files:**
- Modify: `modules/aleph/lib/aleph/keymap.ex`
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (init: `lock?: false`; reads: `lock?:`)
- Test: `modules/aleph/test/aleph/keymap_test.exs`

**Step 1: Failing tests** (keymap_test.exs — mirror the file's existing literal-state idiom;
a minimal world state there looks like
`%{active_key: 0, focus: %Focus{...}, tlon_layout: layout, threads: [], focused_id: nil, ...}` —
copy a neighboring test's fixture):

```elixir
  describe "global Alt chords (clarity slice 4)" do
    # Build on the existing tlon fixtures in this file; layout must have left/right lists.

    test "Alt+digit jumps focus from INSIDE the terminal — implicit nav" do
      state = tlon_state(%{focus: %Focus{in_terminal?: true}})
      {next, :repaint} = Keymap.handle(%{key: :char, char: "2", alt: true}, state)
      assert next.focus.in_terminal? == false
      assert next.focus.column == :left
      assert next.focus.pane == 1
    end

    test "Alt+0 returns to the terminal from nav" do
      state = tlon_state(%{focus: %Focus{in_terminal?: false, column: :left, pane: 1}})
      {next, :repaint} = Keymap.handle(%{key: :char, char: "0", alt: true}, state)
      assert next.focus.in_terminal? == true
    end

    test "Alt+j moves a pane down from the terminal (implicit nav)" do
      state = tlon_state(%{focus: %Focus{in_terminal?: true}})
      {next, :repaint} = Keymap.handle(%{key: :char, char: "j", alt: true}, state)
      assert next.focus.in_terminal? == false
    end

    test "Alt+] cycles the carousel from anywhere" do
      state = tlon_state(%{focus: %Focus{in_terminal?: true}})
      assert {_next, {:cycle_pane_view, 1}} = Keymap.handle(%{key: :char, char: "]", alt: true}, state)
    end

    test "Alt+c opens the composer from the terminal" do
      state = tlon_state(%{focus: %Focus{in_terminal?: true}, composer_thread_id: 7})
      {next, :repaint} = Keymap.handle(%{key: :char, char: "c", alt: true}, state)
      assert next.input.kind == :compose
    end

    test "bare digit in NAV is the fallback jump (leader-digit path)" do
      state = tlon_state(%{focus: %Focus{in_terminal?: false}})
      {next, :repaint} = Keymap.handle(%{key: :char, char: "4"}, state)
      assert next.focus.column == :right
    end
  end

  describe "LOCK mode (clarity slice 4)" do
    test "Alt+g locks; everything then forwards; Alt+g unlocks" do
      state = tlon_state(%{focus: %Focus{in_terminal?: true}, center_live?: true, lock?: false})

      {locked, :repaint} = Keymap.handle(%{key: :char, char: "g", alt: true}, state)
      assert locked.lock?

      # Alt+digit forwards under lock — readline owns it now.
      assert {_s, {:forward, %{key: :char, char: "1", alt: true}}} =
               Keymap.handle(%{key: :char, char: "1", alt: true}, locked)

      # Ctrl+Space forwards too — even the mode toggle is the app's under lock.
      assert {_s, {:forward, %{key: :space, ctrl: true}}} =
               Keymap.handle(%{key: :space, ctrl: true}, locked)

      {unlocked, :repaint} = Keymap.handle(%{key: :char, char: "g", alt: true}, locked)
      refute unlocked.lock?
    end
  end
```

(Write a small `tlon_state/1` helper in the test file if one doesn't exist — a literal map
with `active_key: 0`, a `tlon_layout` whose `left` is
`[Panel.Spaces, Panel.Stack, Panel.Memory]` and `right` is `[Panel.Health, Panel.Crew]`,
plus `threads: []`, `focused_id: nil`, `input: nil`, `leader_pending?: false`,
`center_live?: false`, `composer_thread_id: nil`, `lock?: false`, merged with overrides.)

**Step 2:** run → FAIL.

**Step 3: Implement in `keymap.ex`.** Ordering is everything:

3a. **LOCK clauses at the VERY TOP of `handle/2`** (before even the input-modal clauses —
lock means the center owns literally everything):

```elixir
  # --- LOCK mode (design 2026-08-23): total passthrough. Alt+g alone is aleph's; every other
  # key — Alt chords, the leader, Esc — forwards raw so readline/emacs keep their Alt bindings.
  # Toggled by the same chord. Precedes EVERYTHING, the input modal included.
  def handle(%{key: :char, char: "g", alt: true}, %{lock?: true} = state),
    do: {Map.put(state, :lock?, false), :repaint}

  def handle(key, %{lock?: true, center_live?: true} = state), do: {state, {:forward, key}}
  def handle(_key, %{lock?: true} = state), do: {state, :none}

  def handle(%{key: :char, char: "g", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: {Map.put(state, :lock?, true), :repaint}
```

(`Map.put`, not `%{state | …}` — older test states without `:lock?` must not raise; and
`%{lock?: true}` in a pattern simply doesn't match a map without the key.)

3b. **Global Alt chords** — insert AFTER the input-modal block (the `def handle(_key,
%{input: %{}} = state)` catch-all) and BEFORE the Tlön routing clause
(`def handle(key, %{active_key: k, focus: %Focus{}} = state) when Space.world?(k)`):

```elixir
  # --- Global Alt chords (design 2026-08-23): work from ANY mode — TERM included — and switch
  # mode implicitly. World-only for movement (there's no pane grid elsewhere); n/c everywhere.
  # Must precede the Tlön routing clause (which would forward them to tmux from TERM).
  def handle(%{key: :char, char: d, alt: true} = k, %{active_key: key, focus: %Focus{}} = state)
      when Space.world?(key) and d in ~w(0 1 2 3 4 5 6 7 8 9) and not is_map_key(k, :ctrl),
      do: {focus_jump(state, String.to_integer(d)), :repaint}

  def handle(%{key: :char, char: c, alt: true} = k, %{active_key: key, focus: %Focus{}} = state)
      when Space.world?(key) and c in ~w(h j k l) and not is_map_key(k, :ctrl),
      do: {alt_move(state, c), :repaint}

  def handle(%{key: :char, char: "]", alt: true}, state), do: {state, {:cycle_pane_view, 1}}
  def handle(%{key: :char, char: "[", alt: true}, state), do: {state, {:cycle_pane_view, -1}}

  # Alt+n / Alt+c reach the shared command table with the modifier stripped (its clauses are
  # modifier-guarded on purpose — a bare-shaped key is the door).
  def handle(%{key: :char, char: "n", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "n"}, state)

  def handle(%{key: :char, char: "c", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "c"}, state)
```

with the helpers (near `focus_intent/2`):

```elixir
  defp focus_jump(state, digit), do: %{state | focus: Focus.jump(state.focus, state.tlon_layout, digit)}

  # Alt+h/j/k/l: directional pane movement, implicit nav (Focus intents no-op in-terminal, so
  # drop out of the terminal first).
  @alt_moves %{"h" => :col_left, "l" => :col_right, "j" => :pane_next, "k" => :pane_prev}

  defp alt_move(state, c) do
    focus = %{state.focus | in_terminal?: false}
    %{state | focus: Focus.handle(focus, state.tlon_layout, @alt_moves[c])}
  end
```

3c. **Bare digits in NAV** (the leader-digit fallback) — add to `handle_tlon/2`, after the
Esc clauses and before the `h`/`l` clauses:

```elixir
  # Bare digits in nav: the no-plumbing fallback for the Alt chords (`^␣ 5`) — jump by border
  # number; 0 re-enters the terminal.
  defp handle_tlon(%{key: :char, char: d}, state) when d in ~w(0 1 2 3 4 5 6 7 8 9),
    do: {focus_jump(state, String.to_integer(d)), :repaint}
```

3d. Cockpit wiring: in `init/1`'s state map add `lock?: false,` (next to
`leader_pending?: false`); in `render/1`'s `reads` add `lock?: state.lock?,`. The
`handle_cast({:dispatch, key})` path passes the whole state through, so `lock?` reaches the
keymap already; nothing else to thread.

**Step 4:** run `mise exec -- mix test test/aleph/keymap_test.exs` → PASS, then the full
suite (the Tlön routing tests must still pass — Alt-less keys never touch the new clauses).

**Step 5: Commit:** `aleph: global Alt chords + LOCK mode + bare-digit nav jump`.

### Task 4.3: Numbering agreement test (View borders ⇄ Focus.jump)

**Files:**
- Test: `modules/aleph/test/aleph/view_test.exs`

Pin that the digits View paints are the panes `Focus.jump/3` reaches — the one drift that
would make Alt+N lie:

```elixir
    test "border digits agree with Focus.jump over the same layout (Alt+N reaches pane N)" do
      placements = View.compose(reads(%{}), 120, 40)
      space = Aleph.Space.fetch(0)

      layout = %{
        left: [Panel.Spaces | space.left],
        right: Aleph.Space.visible_right(space, 0),
        sections: %{},
        counts: %{}
      }

      for {Panel.Border, %{digit: d, title: title}, _rect} <- placements,
          is_integer(d) and d > 0 and title != nil do
        pane = Focus.jump(%Focus{}, layout, d) |> Focus.focused_pane(layout)
        # the pane module's title is the border's title
        assert title != nil and pane != nil
      end
    end
```

(Strengthen it: map `pane` through the same title expectation — e.g. build a
`%{1 => Panel.Spaces, 2 => Panel.Stack, ...}` literal and assert
`Focus.jump(%Focus{}, layout, d) |> Focus.focused_pane(layout) == expected[d]` for d 1..5.)
Run, adjust, commit: `aleph: pin digit-numbering agreement between View and Focus.jump`.

### Task 4.4: Slice gate

`mise run aleph:check` → green. Commit anything the formatter touched.

### Task 4.5: LIVE verification in kitty (operator-assisted — do not skip)

This is the slice's known risk. In a real kitty window:

```bash
mise run aleph:run   # or however the cockpit is normally launched (mix task aleph.run)
```

Checklist (report results honestly; a failure here is fine — the fallback ships either way):
1. From TERM (center live), press `Alt+2` → STACK's border goes heavy/accent, footer flips to
   NAV. `Alt+0` → back to TERM.
2. `Alt+j/k/h/l` walk panes from both modes.
3. `Alt+]` flips the carousel tab strip; `Alt+c` opens the composer over the live terminal.
4. `Alt+g` → LOCK chip; inside the center, `Alt+b`/`Alt+f` reach readline (word-jump in a
   shell); `Alt+g` unlocks.
5. `^␣` then a bare digit in NAV also jumps (fallback path).

If Alt arrives mangled (keys leak to tmux, or nothing fires): capture what the parser saw
(`Aleph.CrashLog.path()` for crashes; otherwise add a temporary `IO.inspect` in the dispatch
clause), fix the decode in the `mix.exs` parser patch if it's a missing CSI-u shape, and
re-verify. The bare-digit fallback must work regardless — that's the floor.

---

# Slice 5 — Polish: `[ ] cycle` corner hint

(The heavy accent focused frame already shipped in Border; this slice is just the carousel's
corner hint.)

### Task 5.1: View hangs the hint on the carousel border

**Files:**
- Modify: `modules/aleph/lib/aleph/view.ex`
- Test: `modules/aleph/test/aleph/view_test.exs`

**Test first:**

```elixir
    test "the carousel border carries the [ ] cycle corner hint" do
      placements = View.compose(reads(%{health: health_data()}), 120, 40)

      assert Enum.any?(placements, fn
               {Panel.Border, %{tabs: tabs, hint: "[ ] cycle"}, _r} when is_list(tabs) -> true
               _ -> false
             end)
    end
```

Implement: in `border_data/4` (or wherever the carousel tabs attach), when `tabs != nil` also
set `hint: "[ ] cycle"`. Border already renders `:hint` (Task 1.1).

Run → PASS. `mise run aleph:check`. Commit: `aleph: [ ] cycle hint on the carousel frame`.

---

# Slice 6 — Semantic yank (`y` + OSC 52)

Outcome: `y` in NAV copies the focused item's REAL text — commit SHA (Stack), fact/habit text
(Memory), thread title (Leaves), detail body (open detail) — to the system clipboard via
OSC 52 (works over SSH). Selection story documented.

### Task 6.1: `Aleph.Osc` (pure OSC 52 builder)

**Files:**
- Create: `modules/aleph/lib/aleph/osc.ex`
- Test: `modules/aleph/test/aleph/osc_test.exs`

Test:

```elixir
defmodule Aleph.OscTest do
  use ExUnit.Case, async: true

  test "copy/1 builds an OSC 52 clipboard write with base64 payload" do
    assert Aleph.Osc.copy("abc123") == "\e]52;c;#{Base.encode64("abc123")}\a"
  end
end
```

Implementation:

```elixir
defmodule Aleph.Osc do
  @moduledoc """
  OSC escape builders — pure strings; the caller owns the tty write. OSC 52 sets the system
  clipboard THROUGH the terminal, so it works over SSH (the terminal, not the host, owns the
  clipboard). kitty honors it natively.
  """

  @doc "OSC 52: copy `text` to the system clipboard (`c` selection)."
  @spec copy(String.t()) :: String.t()
  def copy(text), do: "\e]52;c;#{Base.encode64(text)}\a"
end
```

Run → PASS. Commit: `aleph: Aleph.Osc — pure OSC 52 builder`.

### Task 6.2: Per-pane `yank/2` (next to `pick/3`)

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/{stack,memory,leaves}.ex` (+ their tests)

Tests (one per panel test file), e.g. stack:

```elixir
  test "yank/2 returns the cursor commit's full sha" do
    data = %{commits: [%{hash: "abc123", subject: "s", relative: "", date: "", author: "", agent?: false}]}
    assert Aleph.Panel.Stack.yank(data, 0) == {"sha abc123", "abc123"}
    assert Aleph.Panel.Stack.yank(data, 9) == nil
    assert Aleph.Panel.Stack.yank(nil, 0) == nil
  end
```

Implementations (each with a one-line `@doc "The semantic yank for the cursor row."`):

```elixir
# stack.ex
  def yank(%{commits: commits}, cursor) do
    case Enum.at(commits, cursor) do
      %{hash: hash} -> {"sha #{hash}", hash}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil

# memory.ex — section-aware: data carries :section exactly as render does.
  def yank(%{habits: habits, section: @habits_section}, cursor) do
    case Enum.at(habits, cursor) do
      %{text: text} -> {"habit", text}
      _ -> nil
    end
  end

  def yank(%{floor: floor}, cursor) do
    case Enum.at(floor, cursor) do
      %{text: text} -> {"fact", text}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil

# leaves.ex — respect the same ordered/2 the render/pick use, so y hits the row on screen.
  def yank(%{rows: rows} = data, cursor) do
    case Enum.at(ordered(rows, Map.get(data, :focused_lead)), cursor) do
      %{title: title} when is_binary(title) -> {"title", title}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil
```

Also extend each pane's `hints/1` with `{"y", ...}` where missing: Memory →
`{"y", "text"}`, Leaves → `{"y", "title"}` (Stack already has `y sha`).

Run tests → PASS. Commit: `aleph: per-pane yank/2 — the semantic clipboard text`.

### Task 6.3: Keymap `y` → cockpit OSC write

**Files:**
- Modify: `modules/aleph/lib/aleph/keymap.ex` (effect + handle_tlon clause)
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (`apply_effect(:yank, …)` + `yank_text/1`)
- Test: `modules/aleph/test/aleph/keymap_test.exs`

Keymap test:

```elixir
    test "y in nav emits :yank; y in the terminal forwards" do
      nav = tlon_state(%{focus: %Focus{in_terminal?: false}})
      assert {_s, :yank} = Keymap.handle(%{key: :char, char: "y"}, nav)

      term = tlon_state(%{focus: %Focus{in_terminal?: true}})
      assert {_s, {:forward, _}} = Keymap.handle(%{key: :char, char: "y"}, term)
    end
```

Keymap: add `:yank` to the `@type effect` union and, in `handle_tlon/2` (after the `a`/`r`
habit clauses, before the digit clause):

```elixir
  # `y` — semantic yank: the cockpit resolves the focused pane's real text (sha/fact/title)
  # and writes it to the clipboard via OSC 52. Detail-open yanks the detail body.
  defp handle_tlon(%{key: :char, char: "y"}, state), do: {state, :yank}
```

Cockpit — add near the other `apply_effect` clauses:

```elixir
  # `y` landed: resolve the focused pane's semantic text, OSC-52 it to the host clipboard
  # (through the tty, so it works over SSH), and flash what was taken.
  defp apply_effect(:yank, state) do
    case yank_text(state) do
      {label, text} ->
        IO.write(Aleph.Osc.copy(text))
        {:noreply, render(%{state | flash: "yanked #{label}"})}

      nil ->
        {:noreply, render(%{state | flash: "nothing to yank here"})}
    end
  end
```

and near `tlon_detail/2` (same dispatch shape):

```elixir
  # The focused selection's clipboard text — pane dispatch mirrors tlon_detail/2. An open
  # detail wins (yank what's on screen).
  defp yank_text(%{focus: %Focus{detail?: true}} = state) do
    case tlon_detail(state, tlon_layout(state)) do
      %{title: title, lines: lines} -> {"detail", Enum.map_join([{title, nil} | lines], "\n", fn {t, _} -> t end)}
      _ -> nil
    end
  end

  defp yank_text(state) do
    layout = tlon_layout(state)
    cursor = Focus.cursor(state.focus, layout)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Stack -> Panel.Stack.yank(state.stack, cursor)
      Panel.Memory -> Panel.Memory.yank(memory_for_yank(state), cursor)
      Panel.Leaves -> Panel.Leaves.yank(state.leaves, cursor)
      _ -> nil
    end
  end

  defp memory_for_yank(%{memory: nil}), do: nil
  defp memory_for_yank(%{memory: memory, focus: focus}), do: Map.put(memory, :section, focus.section)
```

Run `mise exec -- mix test` → PASS.

### Task 6.4: Document the selection story

Append to `modules/aleph/AGENTS.md` (or its closest "operating the cockpit" section):

```markdown
## Selection & clipboard

- **Arbitrary text:** hold **Shift and drag** — kitty bypasses the cockpit's mouse capture and
  selects natively (inside the center terminal, tmux copy-mode also works as usual).
- **Semantic text:** in NAV, `y` copies the focused item's real text (commit SHA, fact/habit
  text, leaf title, an open detail's body) via OSC 52 — works over SSH.
```

Slice gate `mise run aleph:check`; commit: `aleph: y yanks the focused item over OSC 52`.

---

# Slice 7 — `Aleph.Graphics`: the kitty images seam

Outcome: a capability-gated seam — pure kitty-graphics APC builders + a placement differ —
wired after each paint, with tmux `allow-passthrough` enabled on world sessions and a dormant
Conversation consumer proving the shape. **The seam is the deliverable; real consumers arrive
with the coming Spaces.**

### Task 7.1: `Aleph.Graphics` (pure builders + differ)

**Files:**
- Create: `modules/aleph/lib/aleph/graphics.ex`
- Test: `modules/aleph/test/aleph/graphics_test.exs`

**Step 1: Failing tests:**

```elixir
defmodule Aleph.GraphicsTest do
  use ExUnit.Case, async: true

  alias Aleph.Graphics

  test "transmit/2 chunks base64 PNG into APC sequences, m=1 until the last" do
    png = :crypto.strong_rand_bytes(5000)
    seqs = Graphics.transmit(7, png)

    assert length(seqs) > 1
    assert List.first(seqs) =~ "\e_G"
    assert List.first(seqs) =~ "i=7"
    assert List.first(seqs) =~ "m=1"
    refute List.last(seqs) =~ "m=1"
    assert Enum.all?(seqs, &String.ends_with?(&1, "\e\\"))
  end

  test "place/2 saves the cursor, moves to the cell, places, restores" do
    io = Graphics.place(7, %{x: 4, y: 2, w: 10, h: 5}) |> IO.iodata_to_binary()
    assert io =~ "\e[3;5H"
    assert io =~ "a=p"
    assert io =~ "i=7"
    assert io =~ "c=10,r=5"
  end

  test "delete/1 deletes by id" do
    assert Graphics.delete(7) =~ "a=d,d=i,i=7"
  end

  test "placeholder/2 is a dim run" do
    assert Graphics.placeholder(10, 4) == [{"[image 10x4]", :dim}]
  end

  test "sync/2 transmits once, places every frame, deletes the vanished" do
    wanted = [%{id: 1, data: <<1, 2, 3>>, rect: %{x: 0, y: 0, w: 4, h: 2}}]

    {io1, cache1} = Graphics.sync(wanted, MapSet.new())
    assert IO.iodata_to_binary(io1) =~ "a=t"
    assert MapSet.member?(cache1, 1)

    {io2, _cache2} = Graphics.sync(wanted, cache1)
    refute IO.iodata_to_binary(io2) =~ "a=t"
    assert IO.iodata_to_binary(io2) =~ "a=p"

    {io3, cache3} = Graphics.sync([], cache1)
    assert IO.iodata_to_binary(io3) =~ "a=d"
    refute MapSet.member?(cache3, 1)
  end
end
```

**Step 2:** run → FAIL. **Step 3: Implement:**

```elixir
defmodule Aleph.Graphics do
  @moduledoc """
  The kitty-graphics seam (design 2026-08-23 §Images): pure APC sequence builders + a placement
  differ, capability-gated. Panels declare image placements `%{id, data, rect}` (raw PNG bytes;
  the read that produced the data owns the file IO); `sync/2` diffs them against the
  transmitted-id cache and returns `{iodata, next_cache}` — transmit once per id, place per
  frame, delete what vanished. The tty write is the caller's; everything here is testable.
  Non-kitty hosts skip sync entirely and render `placeholder/2` runs instead.
  """

  @chunk 4096

  @doc "Is the host kitty (or kitty-graphics capable)? Env detection — cheap, per call."
  @spec kitty?() :: boolean()
  def kitty? do
    System.get_env("KITTY_WINDOW_ID") != nil or String.contains?(System.get_env("TERM") || "", "kitty")
  end

  @doc "A dim placeholder run for hosts without graphics."
  @spec placeholder(pos_integer(), pos_integer()) :: [{String.t(), atom()}]
  def placeholder(w, h), do: [{"[image #{w}x#{h}]", :dim}]

  @doc "Transmit PNG bytes under `id` — chunked base64 APC, `m=1` continuation until the last."
  @spec transmit(non_neg_integer(), binary()) :: [String.t()]
  def transmit(id, png) when is_binary(png) do
    chunks = png |> Base.encode64() |> chunk_every()
    last = length(chunks) - 1

    chunks
    |> Enum.with_index()
    |> Enum.map(fn
      {c, 0} when last == 0 -> "\e_Gf=100,a=t,q=2,i=#{id};#{c}\e\\"
      {c, 0} -> "\e_Gf=100,a=t,q=2,i=#{id},m=1;#{c}\e\\"
      {c, ^last} -> "\e_Gm=0;#{c}\e\\"
      {c, _i} -> "\e_Gm=1;#{c}\e\\"
    end)
  end

  @doc "Place transmitted `id` over a cell rect: save cursor, move, place, restore."
  @spec place(non_neg_integer(), Aleph.Panel.rect()) :: iodata()
  def place(id, %{x: x, y: y, w: w, h: h}),
    do: ["\e7", "\e[#{y + 1};#{x + 1}H", "\e_Ga=p,q=2,i=#{id},c=#{w},r=#{h}\e\\", "\e8"]

  @doc "Delete every placement of `id` (scroll/close/resize)."
  @spec delete(non_neg_integer()) :: String.t()
  def delete(id), do: "\e_Ga=d,d=i,i=#{id},q=2\e\\"

  @doc """
  Diff wanted placements against the transmitted-id cache → `{iodata_to_write, next_cache}`.
  """
  @spec sync([%{id: non_neg_integer(), data: binary(), rect: map()}], MapSet.t()) :: {iodata(), MapSet.t()}
  def sync(wanted, cache) do
    wanted_ids = MapSet.new(wanted, & &1.id)

    transmits = for p <- wanted, not MapSet.member?(cache, p.id), do: transmit(p.id, p.data)
    places = Enum.map(wanted, &place(&1.id, &1.rect))
    deletes = for id <- MapSet.difference(cache, wanted_ids), do: delete(id)

    {[transmits, places, deletes], MapSet.union(wanted_ids, MapSet.new())}
  end

  defp chunk_every(b64) do
    b64
    |> Stream.unfold(fn
      "" -> nil
      s -> String.split_at(s, @chunk)
    end)
    |> Enum.to_list()
  end
end
```

(Watch `sync/2`'s cache return: the next cache is `wanted_ids` — a deleted id must drop OUT of
the cache so a re-appearing image re-transmits. The test pins this.)

**Step 4:** run → PASS. **Commit:** `aleph: Aleph.Graphics — kitty APC builders + placement differ`.

### Task 7.2: Cockpit wiring — sync after paint, gate on kitty

**Files:**
- Modify: `modules/aleph/lib/aleph/cockpit.ex`

1. `init/1` state: add `graphics: MapSet.new(),`.
2. Panels opt in with an optional callback — add to `panel.ex`:

```elixir
  @doc "Image placements to draw over this panel's rect (kitty hosts) — `%{id, data, rect}`s."
  @callback images(data :: term(), rect()) :: [map()]

  @optional_callbacks [pick: 3, hints: 1, images: 2]

  @doc "A panel's image placements, or [] — `images/2` is optional."
  @spec images(module(), term(), rect()) :: [map()]
  def images(panel, data, rect) do
    if function_exported?(panel, :images, 2), do: panel.images(data, rect) || [], else: []
  end
```

3. In `render/1`, after `Board.paint()`:

```elixir
    placements
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    state = sync_graphics(state, placements)

    %{state | placements: placements}
```

with:

```elixir
  # The kitty-graphics pass (design 2026-08-23): after the cell paint, place/refresh every
  # panel-declared image. Non-kitty hosts skip it wholesale (panels showed placeholder runs).
  defp sync_graphics(state, placements) do
    if Aleph.Graphics.kitty?() do
      wanted =
        Enum.flat_map(placements, fn {panel, data, rect} ->
          panel_mod = panel_module(panel)
          Panel.images(panel_mod, data, rect)
        end)

      {io, cache} = Aleph.Graphics.sync(wanted, state.graphics)
      if io != [[], [], []], do: IO.write(io)
      %{state | graphics: cache}
    else
      state
    end
  end

  defp panel_module({panel, _read_key}), do: panel
  defp panel_module(panel), do: panel
```

(If a `panel_module/1` helper already exists under another name, reuse it.)

4. Resize/teardown hygiene: in the `:resize` handler and `terminate/2`, clear placements —
   `IO.write(Aleph.Graphics.delete_all())` — add to Graphics:

```elixir
  @doc "Delete EVERY placement (resize/teardown)."
  def delete_all, do: "\e_Ga=d,d=a,q=2\e\\"
```

  and reset `graphics: MapSet.new()` in the resize path.

No unit test can drive the tty write; the differ is already covered. Run the full suite for
regressions.

**Commit:** `aleph: graphics sync pass after paint, kitty-gated`.

### Task 7.3: tmux `allow-passthrough` rider

**Files:**
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (`ensure_center/3`, ~line 1833)

After the world session is ensured/spawned in `ensure_center` (the success path — find where
the `profile_launcher`-built `new-session -A` command has run), add:

```elixir
    # Harnesses inside the center can emit kitty graphics themselves — tmux must pass the APC
    # through instead of eating it (design 2026-08-23 §Images rider).
    _ = tlon_run(world_id, ["set-option", "-g", "allow-passthrough", "on"])
```

(One call per ensure is idempotent and cheap; `tlon_run/2` is the existing best-effort tmux
runner.) Verify by hand later: `tmux -L aleph-world-<id> show-options -g allow-passthrough`.

**Commit:** `aleph: world tmux sessions allow-passthrough (graphics rider)`.

### Task 7.4: Dormant Conversation consumer (placeholder path only)

**Files:**
- Modify: `modules/aleph/lib/aleph/panel/conversation.ex`
- Test: `modules/aleph/test/aleph/panel/conversation_test.exs`

Test first: a message map carrying `attachment: %{w: 24, h: 6}` renders a
`Graphics.placeholder(24, 6)` row after its body. Implement by appending the placeholder row
in the message-rendering path when `msg[:attachment]` is present (match tolerantly —
`Map.get(msg, :attachment)`). Funes doesn't emit attachments yet, so this is the seam's proof,
not a feature; note that in the panel's moduledoc. Real thumbnails (`images/2` on
Conversation + the funes attachment write-path) land with the new Spaces work — out of scope
here.

**Slice gate:** `mise run aleph:check` → green.

**Commit:** `aleph: conversation renders attachment placeholders (graphics seam consumer)`.

---

## Final verification (after slice 7)

1. `mise run aleph:check` — green.
2. From repo root: `mise run flake:check` if the machine gate is expected before calling the
   branch done (see `verify-with-home-switch-before-done`) — or explicitly flag it unverified.
3. Live pass in kitty (one sweep): every pane by digit (`Alt+1..5`, `Alt+0`), carousel by
   `[`/`]`/click/`Alt+]`, footer changes per mode + per focused pane, HABITS absent when
   empty, shift+drag selection, one `y` yank pasted somewhere, LOCK round-trip. Under a
   non-kitty TERM (e.g. `TERM=xterm-256color`), confirm the cockpit still boots and the
   graphics pass stays silent.
4. Update the memory file `aleph-cockpit-clarity-design.md` (auto-memory) to record what
   landed.
