defmodule Aleph.Tlon.FocusTest do
  @moduledoc """
  The Tlön lazygit focus state machine (design: docs/plans/2026-08-20-tlon-lazygit-panels-design.md):
  a pure reducer over (which column, which pane in it, which section, in the terminal?). Render and
  tmux wiring hang off it; this asserts the navigation contract headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Tlon.Focus

  # left column stacks Commits then Memory (3 sections); right column is Leaves (1 section).
  @layout %{left: [:commits, :memory], right: [:leaves], sections: %{commits: 1, memory: 3, leaves: 1}}

  defp nav, do: Focus.handle(Focus.new(), @layout, :toggle_terminal)

  describe "the terminal toggle" do
    test "starts in the terminal" do
      assert Focus.new().in_terminal?
    end

    test "Ctrl+Space toggles out to nav mode, landing on the first left pane" do
      s = nav()
      refute s.in_terminal?
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "Ctrl+Space toggles back into the terminal" do
      s = Focus.handle(nav(), @layout, :toggle_terminal)
      assert s.in_terminal?
    end

    test "nav intents are no-ops while in the terminal (keys belong to tmux)" do
      s = Focus.handle(Focus.new(), @layout, :pane_next)
      assert s == Focus.new()
    end
  end

  describe "h/l — panes up/down a column" do
    test "l moves to the next pane, clamping at the bottom" do
      s = Focus.handle(nav(), @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
      s = Focus.handle(s, @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
    end

    test "h moves to the previous pane, clamping at the top" do
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :pane_prev)
      assert Focus.focused_pane(s, @layout) == :commits
      s = Focus.handle(s, @layout, :pane_prev)
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "moving pane resets the section" do
      # onto memory, advance a section, then move off — the section clears
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 1
      assert Focus.handle(s, @layout, :pane_prev).section == 0
    end
  end

  describe "H/L — between columns" do
    test "L jumps to the right column's first pane" do
      s = Focus.handle(nav(), @layout, :col_right)
      assert Focus.focused_pane(s, @layout) == :leaves
    end

    test "H jumps back to the left column, clamping the pane index" do
      s =
        nav()
        |> Focus.handle(@layout, :pane_next)
        |> Focus.handle(@layout, :col_right)
        |> Focus.handle(@layout, :col_left)

      # left has 2 panes; a right index of 0 clamps fine, lands on the first left pane
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "switching column resets the section" do
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 1
      assert Focus.handle(s, @layout, :col_right).section == 0
    end
  end

  describe "Tab — sections within a pane" do
    test "cycles through a multi-section pane and wraps" do
      s = Focus.handle(nav(), @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
      s = Focus.handle(s, @layout, :section_next)
      assert s.section == 1
      s = s |> Focus.handle(@layout, :section_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 0
    end

    test "a single-section pane stays put" do
      s = Focus.handle(nav(), @layout, :section_next)
      assert s.section == 0
    end
  end
end
