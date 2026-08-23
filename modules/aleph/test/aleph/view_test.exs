defmodule Aleph.ViewTest do
  @moduledoc """
  The composition layer as plain data (design §3): `Aleph.View.compose/3` turns the assembled
  reads + a size into placed `{panel, data, rect}` boxes, no TTY. These tests pin the Tlön focus
  highlight — the lazygit "active pane" cue — so a regression (nothing lights, or the wrong column
  lights) is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Panel
  alias Aleph.Tlon.Focus
  alias Aleph.View

  # A minimal reads map: compose only needs the keys to exist (it lays out boxes; panel content is
  # rendered later), so the data can be empty/nil. Overrides set the space + focus under test.
  defp reads(overrides) do
    Map.merge(
      %{
        active_key: 0,
        focus: nil,
        focused_id: nil,
        focused_title: nil,
        threads: [],
        roster: [],
        scope: nil,
        chatter: [],
        chorus: [],
        terminal: :no_session,
        machine: :no_session,
        stack: nil,
        health: nil,
        orbis: nil,
        logbook: nil,
        triage: nil,
        habits: nil,
        settings: nil,
        scrolls: %{},
        input: nil,
        flash: nil,
        leader_pending?: false,
        tlon_layout: nil,
        detail: nil
      },
      overrides
    )
  end

  # A Tlön layout with commits count, so Focus.cursor/2 clamps and the Commits pane is navigable.
  # SPACES leads the left column, matching production `tlon_layout` (View prepends it on screen too).
  defp layout(counts \\ %{Panel.Stack => 3}),
    do: %{
      left: [Panel.Spaces, Panel.Stack, Panel.Settings],
      right: [Panel.Health, Panel.Leaves],
      sections: %{},
      counts: counts
    }

  # The rects of every border flagged as focused.
  defp focused_borders(placements), do: for({Panel.Border, %{focused: true}, rect} <- placements, do: rect)

  describe "Tlön focus highlight" do
    test "in nav mode, exactly one sidebar border lights — the focused pane, in the left column" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The left column sits at x = 0 (wide layout); the focused pane must be there.
      assert rect.x == 0
    end

    test "focusing the right column moves the highlight to a right-column border" do
      focus = %Focus{in_terminal?: false, column: :right, pane: 0}
      placements = View.compose(reads(%{focus: focus}), 120, 40)

      assert [rect] = focused_borders(placements)
      # The right column is offset well past the left — not at x = 0.
      assert rect.x > 0
    end

    test "in the terminal (default focus), no border is highlighted — the terminal is the active pane" do
      placements = View.compose(reads(%{focus: Focus.new()}), 120, 40)
      assert focused_borders(placements) == []
    end

    test "a non-Tlön space (focus nil) never highlights a border" do
      placements = View.compose(reads(%{active_key: :orbis, focus: nil}), 120, 40)
      assert focused_borders(placements) == []
    end
  end

  describe "MAIN detail (Enter)" do
    # The Terminal keyed section, if present.
    defp terminal_placed?(placements), do: Enum.any?(placements, &match?({Panel.Terminal, _, _}, &1))

    defp detail_placed?(placements), do: Enum.any?(placements, &match?({Panel.Detail, _, _}, &1))

    test "with a detail open and resolved, MAIN shows Panel.Detail instead of the terminal" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}
      detail = %{title: "commit abc · x", lines: [{"+added", :diff_add}]}

      placements =
        View.compose(reads(%{focus: focus, tlon_layout: layout(), detail: detail}), 120, 40)

      assert detail_placed?(placements)
      refute terminal_placed?(placements)
    end

    test "detail? on but nothing resolved (nil) leaves the terminal in place" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 0, detail?: true}

      placements =
        View.compose(reads(%{focus: focus, tlon_layout: layout(), detail: nil}), 120, 40)

      refute detail_placed?(placements)
      assert terminal_placed?(placements)
    end
  end

  describe "Orbis' author face (D2.1)" do
    defp chorus_placed?(placements), do: Enum.any?(placements, &match?({Panel.Chorus, _, _}, &1))
    defp author_placed?(placements), do: Enum.any?(placements, &match?({Panel.Author, _, _}, &1))

    test "orbis_face == :author replaces Chorus with Panel.Author" do
      placements = View.compose(reads(%{active_key: :orbis, orbis_face: :author}), 120, 40)
      assert author_placed?(placements)
      refute chorus_placed?(placements)
    end

    test "orbis_face == :survey (the default) keeps Chorus, no Panel.Author" do
      placements = View.compose(reads(%{active_key: :orbis, orbis_face: :survey}), 120, 40)
      refute author_placed?(placements)
      assert chorus_placed?(placements)
    end

    test "orbis_face absent from reads (an older/minimal reads map) defaults to the survey" do
      placements = View.compose(reads(%{active_key: :orbis}), 120, 40)
      refute author_placed?(placements)
      assert chorus_placed?(placements)
    end

    test "orbis_face == :author outside Orbis is inert — only Orbis' center swaps" do
      placements = View.compose(reads(%{active_key: 0, orbis_face: :author}), 120, 40)
      refute author_placed?(placements)
    end
  end

  describe "item selection" do
    # The data handed to a given panel module in the placements.
    defp panel_data(placements, mod) do
      Enum.find_value(placements, fn
        {^mod, data, _rect} -> {:ok, data}
        _ -> nil
      end)
    end

    test "the focused pane gets its cursor + section as a slice; other panes don't" do
      # pane 1 = Stack (SPACES leads the left column at index 0).
      focus = %Focus{
        in_terminal?: false,
        column: :left,
        pane: 1,
        cursors: %{Panel.Stack => 2},
        section: 0,
        detail?: false
      }

      stack = %{
        branch: nil,
        dirty: false,
        ahead: nil,
        behind: nil,
        status_summary: nil,
        commits: [],
        tools: []
      }

      memory = %{coverage: nil, floor: [], habits: []}

      placements =
        View.compose(
          reads(%{focus: focus, tlon_layout: layout(), stack: stack, memory: memory}),
          120,
          40
        )

      assert {:ok, %{selected: 2, section: 0}} = panel_data(placements, Panel.Stack)
      # the other left-column pane (Memory, not focused) gets no slice merged in
      assert {:ok, mem} = panel_data(placements, Panel.Memory)
      refute Map.has_key?(mem, :selected)
    end
  end

  # C3.4: the right column shows ONE panel at a time — `[`/`]` cycle it (right_pane_view) instead
  # of stacking the whole `space.right` list, so the shown panel renders full-height.
  describe "right-pane view (C3.4)" do
    defp right_placed?(placements, mod), do: Enum.any?(placements, &match?({^mod, _, _}, &1))

    test "right_pane_view: 0 (default) shows only the first right panel (Health)" do
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 0})
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Health)
      refute right_placed?(placements, Panel.Leaves)
    end

    test "right_pane_view: 1 shows only the second right panel (Crew), not Health or Leaves" do
      # The World space's right column is [Health, Crew, Activity, Leaves] (Aleph.Space).
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 1})
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Crew)
      refute right_placed?(placements, Panel.Health)
      refute right_placed?(placements, Panel.Leaves)
    end

    test "a missing right_pane_view (key absent from reads) defaults to 0 (the first panel)" do
      r = Map.delete(reads(%{active_key: 0, tlon_layout: layout()}), :right_pane_view)
      placements = View.compose(r, 120, 40)

      assert right_placed?(placements, Panel.Health)
      refute right_placed?(placements, Panel.Leaves)
    end

    test "a 1-panel right column (Orbis' [Dossier]) degrades cleanly — rem clamps to index 0" do
      r = reads(%{active_key: :orbis, focus: nil, right_pane_view: 7})
      placements = View.compose(r, 120, 40)
      assert right_placed?(placements, Panel.Dossier)
    end

    test "narrow layout applies the same single-pane selection to the right portion" do
      r = reads(%{active_key: 0, tlon_layout: layout(), right_pane_view: 1})
      placements = View.compose(r, 60, 40)

      assert right_placed?(placements, Panel.Crew)
      refute right_placed?(placements, Panel.Health)
      refute right_placed?(placements, Panel.Leaves)
    end
  end

  # C3.1: the tab strip is LEADERS only — a world's roster windows (+ the uqbar console furniture);
  # `t<id>` leaf windows move to the Leaves panel, not the strip.
  describe "WindowBar leaders only" do
    defp tab(name), do: %{name: name, active?: false, index: "1"}

    test "leaf windows (t<id>) are excluded from the tab strip; leaders (roster + uqbar) stay" do
      r = reads(%{active_key: 0, machine: %{tabs: [tab("tertius"), tab("hronir"), tab("uqbar"), tab("t42")]}})

      %{tabs: tabs} = View.data_for(Panel.WindowBar, r)
      names = Enum.map(tabs, & &1.name)

      assert "tertius" in names
      assert "hronir" in names
      assert "uqbar" in names
      refute "t42" in names
    end
  end

  describe "compose box" do
    defp composer_placements(placements), do: for({Panel.Composer, data, rect} <- placements, do: {data, rect})

    test "no composer is placed while the input is closed" do
      assert composer_placements(View.compose(reads(%{}), 120, 40)) == []
    end

    test "an open composer places a box above the status bar sized to the wrapped line count" do
      input = %{kind: :compose, thread_id: 1, buffer: "one\ntwo\nthree", cursor: 13}
      placements = View.compose(reads(%{input: input}), 120, 40)

      assert [{%{input: ^input}, rect}] = composer_placements(placements)
      assert rect.h == 3
      # Directly above the 2-row status footer, full width.
      assert rect.y == 40 - 2 - 3
      assert rect.w == 120
    end

    test "the box height caps at half the frame — a huge draft scrolls instead of swallowing the screen" do
      buffer = Enum.map_join(1..60, "\n", &"l#{&1}")
      input = %{kind: :compose, thread_id: 1, buffer: buffer, cursor: String.length(buffer)}

      assert [{_data, rect}] = composer_placements(View.compose(reads(%{input: input}), 120, 40))
      assert rect.h == 20
    end
  end
end
