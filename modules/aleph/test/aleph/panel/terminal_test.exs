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

  describe "Claude Code's cyan `background` sentinel is neutralized, never blitted" do
    # CC paints its theme `background` token — a deliberately garish "you should never see this"
    # cyan (dark UI: rgb(0,204,204); light: rgb(0,153,153)) — as the explicit per-cell bg on
    # queued/injected message rows. The VT stores it faithfully, so aleph must remap it to the
    # panel's own default (black) or those rows blit as cyan under a phosphor theme.
    test "a cyan-sentinel cell background is remapped to the terminal default (black)" do
      rs = render_state(%{cells: [[{"m", {51, 255, 0}, {0, 204, 204}, 0}]]})
      [first | _] = Terminal.render(rs, @rect)
      {char, {:rgb, fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
      assert {char, fg, bg} == {"m", 0x33FF00, 0x000000}
    end

    test "the light-UI sentinel rgb(0,153,153) is remapped too" do
      rs = render_state(%{cells: [[{"m", {51, 255, 0}, {0, 153, 153}, 0}]]})
      [first | _] = Terminal.render(rs, @rect)
      {_, {:rgb, _fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
      assert bg == 0x000000
    end

    test "a normal (non-sentinel) cell background is preserved untouched" do
      rs = render_state(%{cells: [[{"m", {51, 255, 0}, {16, 32, 24}, 0}]]})
      [first | _] = Terminal.render(rs, @rect)
      {_, {:rgb, _fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
      assert bg == 0x102018
    end
  end

  describe "tab_at_x/2: which tab a click landed on" do
    # Layout: " pi " (cols 0-3), " claude " (cols 4-11). Shares tab_label/1 with the render so the
    # clickable regions match what's drawn.
    @tabs [%{name: "pi", active?: true}, %{name: "claude", active?: false}]

    test "a click inside a tab's ` name ` segment returns that tab" do
      assert Terminal.tab_at_x(@tabs, 1).name == "pi"
      assert Terminal.tab_at_x(@tabs, 5).name == "claude"
    end

    test "a click past the last tab is nil — no misfire on the filler" do
      assert Terminal.tab_at_x(@tabs, 40) == nil
    end
  end
end
