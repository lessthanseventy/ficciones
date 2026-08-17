defmodule Aleph.Panel.TerminalTest do
  @moduledoc """
  The center terminal is mostly cell-blitting (eye-tested live), but the Tlön tab strip is a pure
  seam: a window list in → aleph's own header row out (tmux's status bar is off, so this IS the
  window chrome). A wrong strip is a misleading or missing tab, so it earns a test.
  """
  use ExUnit.Case, async: true

  alias Aleph.Panel.Terminal

  @rect %{x: 0, y: 0, w: 40, h: 5}

  defp render_state(over \\ %{}) do
    Map.merge(%{cells: [[{"x", {200, 200, 200}, {0, 0, 0}, 0}]], cursor: %{visible: false}}, over)
  end

  test "with no window list, the terminal renders edge-to-edge (a Sessions coworker)" do
    [first | _] = Terminal.render(render_state(), @rect)
    text = Enum.map_join(first, fn {t, _} -> t end)
    assert text =~ "x"
  end

  test "a window list becomes the header row — active is :selected, the rest :dim" do
    tabs = [%{name: "pi", active?: true}, %{name: "claude", active?: false}]
    [header | rest] = Terminal.render(render_state(%{tabs: tabs}), @rect)

    text = Enum.map_join(header, fn {t, _} -> t end)
    assert text =~ "pi"
    assert text =~ "claude"
    assert Enum.any?(header, fn {t, s} -> t =~ "pi" and s == :selected end)
    assert Enum.any?(header, fn {t, s} -> t =~ "claude" and s == :dim end)

    # the terminal's own cells render BELOW the tab strip
    below = rest |> List.flatten() |> Enum.map_join(fn {t, _} -> t end)
    assert below =~ "x"
  end
end
