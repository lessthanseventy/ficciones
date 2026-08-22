defmodule Aleph.ViewTest do
  @moduledoc """
  The composition layer as plain data (design §3): `Aleph.View.compose/3` turns the assembled
  reads + a size into placed `{panel, data, rect}` boxes, no TTY. These tests pin the Tlön focus
  highlight — the lazygit "active pane" cue — so a regression (nothing lights, or the wrong column
  lights) is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Board
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

  # The settings modal (design §Settings) is a floating overlay, not a column swap: appended last so
  # its opaque box paints over the frame + the live terminal underneath.
  describe "settings modal overlay" do
    @modal %{
      row: 0,
      field: :model,
      rows: [
        %{
          profile: "tertius",
          model: %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
          ring: [%{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}],
          override?: false,
          yolo?: true
        }
      ]
    }

    test "closed (no modal read) places no overlay — the panes render normally" do
      placements = View.compose(reads(%{modal: nil}), 120, 40)
      refute Enum.any?(placements, &match?({Panel.SettingsModal, _, _}, &1))
    end

    test "open: places the modal body centered, over an opaque focused border box" do
      placements = View.compose(reads(%{modal: @modal}), 120, 40)
      assert Enum.any?(placements, &match?({Panel.SettingsModal, _, _}, &1))

      # focus is nil here, so the ONLY focused border is the modal's — and it's horizontally centered.
      [rect] = focused_borders(placements)
      assert rect.w == 60
      assert rect.x == div(120 - 60, 2)
    end

    test "the overlay is painted LAST so it wins the cells under it (last-placement-wins)" do
      placements = View.compose(reads(%{modal: @modal}), 120, 40)
      {tail_panel, _, _} = List.last(placements)
      assert tail_panel == Panel.SettingsModal
    end

    test "opaque: the modal box paints a cell at every coordinate of its rect (no terminal bleed-through)" do
      placements = View.compose(reads(%{modal: @modal}), 120, 40)
      [rect] = focused_borders(placements)

      overlay = for {p, _, _} = pl <- placements, p in [Panel.Border, Panel.SettingsModal], do: pl
      coords = MapSet.new(Board.compose(overlay, 120, 40), &{&1.x, &1.y})

      for x <- rect.x..(rect.x + rect.w - 1), y <- rect.y..(rect.y + rect.h - 1) do
        assert MapSet.member?(coords, {x, y}),
               "modal left cell (#{x},#{y}) unpainted — terminal would show through"
      end
    end
  end
end
