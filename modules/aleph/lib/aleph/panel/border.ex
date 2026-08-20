defmodule Aleph.Panel.Border do
  @moduledoc """
  A rounded box that frames a column so a section reads as a defined region (not text floating
  against the frame). Rendered *under* the panel(s) it wraps — `Aleph.View` places the border
  first and the panels at an inset rect, so their content paints over the box interior and only
  the frame survives. Drawn in the `:separator` style; the interior is left neutral. A `%{focused:
  true}` box (Tlön's focused pane in nav mode) draws its frame in `:accent` instead — the lazygit
  "active pane" cue.
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(%{focused: true}, rect), do: box(rect, :accent)
  def render(_data, rect), do: box(rect, :separator)

  defp box(%{w: w, h: h} = rect, style) when w >= 2 and h >= 2 do
    inner = w - 2

    top = [{"╭" <> String.duplicate("─", inner) <> "╮", style}]
    bottom = [{"╰" <> String.duplicate("─", inner) <> "╯", style}]
    side = [{"│", style}, {String.duplicate(" ", inner), :normal}, {"│", style}]

    Panel.clip([top] ++ List.duplicate(side, h - 2) ++ [bottom], rect)
  end

  defp box(_rect, _style), do: []
end
