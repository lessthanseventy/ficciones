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
        active_key: :tlon,
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
        leader_pending?: false
      },
      overrides
    )
  end

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
end
