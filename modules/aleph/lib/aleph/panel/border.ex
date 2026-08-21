defmodule Aleph.Panel.Border do
  @moduledoc """
  A rounded box that frames a column so a section reads as a defined region (not text floating
  against the frame). Rendered *under* the panel(s) it wraps — `Aleph.View` places the border
  first and the panels at an inset rect, so their content paints over the box interior and only
  the frame survives. Drawn in the `:separator` style with a thin single-line rule. A `%{focused:
  true}` box (Tlön's focused pane in nav mode) draws its frame in `:accent` AND swaps to a heavy
  double-line rule — the lazygit "active pane" cue reads at a glance even before colour registers.
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  # {corner_tl, corner_tr, corner_bl, corner_br, horizontal, vertical} per weight. The focused pane
  # gets the double rule so the active frame is legible on its shape alone (colour-blind / dim-term).
  @thin {"╭", "╮", "╰", "╯", "─", "│"}
  @heavy {"╔", "╗", "╚", "╝", "═", "║"}

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(%{focused: true}, rect), do: box(rect, :accent, @heavy)
  def render(_data, rect), do: box(rect, :separator, @thin)

  defp box(%{w: w, h: h} = rect, style, {tl, tr, bl, br, horiz, vert}) when w >= 2 and h >= 2 do
    inner = w - 2
    rule = String.duplicate(horiz, inner)

    top = [{tl <> rule <> tr, style}]
    bottom = [{bl <> rule <> br, style}]
    side = [{vert, style}, {String.duplicate(" ", inner), :normal}, {vert, style}]

    Panel.clip([top] ++ List.duplicate(side, h - 2) ++ [bottom], rect)
  end

  defp box(_rect, _style, _glyphs), do: []
end
