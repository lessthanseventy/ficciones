defmodule Aleph.Panel.Border do
  @moduledoc """
  A rounded box that frames a column so a section reads as a defined region (not text floating
  against the frame). Rendered *under* the panel(s) it wraps — `Aleph.View` places the border
  first and the panels at an inset rect, so their content paints over the box interior and only
  the frame survives. Drawn in the `:separator` style; the interior is left neutral.
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(_data, %{w: w, h: h} = rect) when w >= 2 and h >= 2 do
    inner = w - 2

    top = [{"╭" <> String.duplicate("─", inner) <> "╮", :separator}]
    bottom = [{"╰" <> String.duplicate("─", inner) <> "╯", :separator}]
    side = [{"│", :separator}, {String.duplicate(" ", inner), :normal}, {"│", :separator}]

    Panel.clip([top] ++ List.duplicate(side, h - 2) ++ [bottom], rect)
  end

  def render(_data, _rect), do: []
end
