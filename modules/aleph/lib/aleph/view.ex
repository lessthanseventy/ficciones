defmodule Aleph.View do
  @moduledoc """
  Composition: turn the cockpit's state into placed panels (design §3, "a view is plain data").
  Given the assembled funes `reads` and the terminal size, `compose/3` lays out the fixed frame —
  left sidebar (space picker + the active space's situational panels), the center surface,
  the right sidebar, the two column rules, and the status bar — as a list of `{panel, data, rect}`
  placements the `Aleph.Board` paints. Pure and testable: no TTY, no funes calls here.

  `reads` is the map the Cockpit assembles:
    `%{active_key, focused_id, focused_title, roster, threads, scope, chatter, session}`
  """
  alias Aleph.{Panel, Space}

  @min_col 16
  # The bottom footer: an info line + a hints line (Aleph.Panel.StatusBar).
  @status_h 2

  @spec compose(map(), pos_integer(), pos_integer()) :: [Aleph.Board.placement()]
  def compose(reads, w, h) do
    space = Space.fetch(reads.active_key)
    body_h = max(h - @status_h, 1)

    left_w = clamp_col(div(w, 4), w)
    right_w = clamp_col(div(w, 4), w)
    center_w = max(w - left_w - right_w - 2, 1)
    center_x = left_w + 1
    right_x = center_x + center_w + 1
    right_w = max(w - right_x, 1)

    {center_panel, _key} = space.surface

    # Each column is a bordered box; a 1-col gap between boxes replaces the old vertical rules.
    columns = [
      {%{x: 0, y: 0, w: left_w, h: body_h}, [Panel.Spaces | space.left]},
      {%{x: center_x, y: 0, w: center_w, h: body_h}, [center_panel]},
      {%{x: right_x, y: 0, w: right_w, h: body_h}, space.right}
    ]

    borders = Enum.map(columns, fn {rect, _panels} -> {Panel.Border, nil, rect} end)

    contents =
      columns
      |> Enum.flat_map(fn {rect, panels} ->
        %{x: ix, y: iy, w: iw, h: ih} = inset(rect)
        stack(panels, ix, iy, iw, ih)
      end)
      |> Enum.map(fn {panel, rect} -> {panel, data_for(panel, reads), rect} end)

    status =
      {Panel.StatusBar, status_data(reads, space), %{x: 0, y: h - @status_h, w: w, h: @status_h}}

    # Borders first: panel content paints over the box interior, leaving only the frame.
    borders ++ contents ++ [status]
  end

  # The content region inside a column box: one cell of frame + one of padding on each side.
  defp inset(%{x: x, y: y, w: w, h: h}) do
    %{x: x + 2, y: y + 1, w: max(w - 4, 1), h: max(h - 2, 1)}
  end

  @doc "Resolve the data a panel is fed from the assembled reads (keeps spaces plain data)."
  def data_for(Panel.Spaces, r), do: %{spaces: Space.all(), active_key: r.active_key}
  def data_for(Panel.Roster, r), do: r.roster

  def data_for(Panel.ThreadList, r),
    do: %{threads: r.threads, roster: r.roster, selected_id: r.focused_id}

  def data_for(Panel.Dossier, r), do: r.scope
  def data_for(Panel.Conversation, r), do: %{title: r.focused_title, messages: r.chatter}
  def data_for(Panel.Session, r), do: r.session
  def data_for(_other, _r), do: nil

  defp status_data(reads, space) do
    %{
      space: space.label,
      thread: reads.focused_title,
      thread_count: length(reads.threads),
      live_count: Enum.count(reads.roster, & &1.warm?)
    }
  end

  # Stack panels vertically in a column: the picker takes a fixed height, the rest split the
  # remainder evenly (the last absorbs the rounding remainder so no row is left unpainted).
  defp stack([], _x, _y0, _w, _h), do: []

  defp stack(panels, x, y0, w, total_h) do
    heights = split_heights(panels, total_h)

    {placed, _y} =
      Enum.zip(panels, heights)
      |> Enum.map_reduce(y0, fn {panel, ph}, y ->
        {{panel, %{x: x, y: y, w: w, h: ph}}, y + ph}
      end)

    placed
  end

  defp split_heights(panels, total_h) do
    fixed = Enum.map(panels, &fixed_height/1)
    fixed_sum = fixed |> Enum.reject(&is_nil/1) |> Enum.sum()
    flex_count = Enum.count(fixed, &is_nil/1)
    flex = if flex_count > 0, do: max(div(total_h - fixed_sum, flex_count), 1), else: 0

    resolved = Enum.map(fixed, fn f -> f || flex end)
    # Hand any rounding remainder to the last panel so the column is fully used.
    used = Enum.sum(resolved)
    List.update_at(resolved, -1, &(&1 + max(total_h - used, 0)))
  end

  # The picker is intrinsically short (header + one row per space); everything else flexes.
  defp fixed_height(Panel.Spaces), do: length(Space.all()) + 3
  defp fixed_height(_panel), do: nil

  defp clamp_col(v, w), do: v |> max(@min_col) |> min(max(div(w, 3), @min_col))
end
