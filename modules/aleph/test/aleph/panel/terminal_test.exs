defmodule Aleph.Panel.TerminalTest do
  @moduledoc """
  The center terminal is mostly cell-blitting (eye-tested live) — it renders edge-to-edge, no
  header row (the Tlön window strip moved out to `Aleph.Panel.WindowBar`; see its own test).
  """
  use ExUnit.Case, async: true

  alias Aleph.Panel.Terminal

  @rect %{x: 0, y: 0, w: 40, h: 5}

  defp render_state(over \\ %{}) do
    Map.merge(%{cells: [[{"x", {200, 200, 200}, {0, 0, 0}, 0}]], cursor: %{visible: false}}, over)
  end

  test "renders cells edge-to-edge, no header row" do
    [first | _] = Terminal.render(render_state(), @rect)
    text = Enum.map_join(first, fn {t, _} -> t end)
    assert text =~ "x"
  end
end
