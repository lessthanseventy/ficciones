defmodule Aleph.View do
  @moduledoc """
  Composition: turn the cockpit's state into placed panels (design §3, "a view is plain data").
  Given the assembled funes `reads` and the terminal size, `compose/3` lays out the fixed frame —
  left sidebar (workspace picker + the active workspace's situational panels), the center surface,
  the right sidebar, the two column rules, and the status bar — as a list of `{panel, data, rect}`
  placements the `Aleph.Board` paints. Pure and testable: no TTY, no funes calls here.

  `reads` is the map the Cockpit assembles:
    `%{active_key, focused_id, focused_title, roster, threads, scope, chatter, session}`
  """
  alias Aleph.{Panel, Workspace}

  @min_col 16

  @spec compose(map(), pos_integer(), pos_integer()) :: [Aleph.Board.placement()]
  def compose(reads, w, h) do
    ws = Workspace.fetch(reads.active_key)
    body_h = max(h - 1, 1)

    left_w = clamp_col(div(w, 4), w)
    right_w = clamp_col(div(w, 4), w)
    center_w = max(w - left_w - right_w - 2, 1)
    rule1_x = left_w
    center_x = left_w + 1
    rule2_x = center_x + center_w
    right_x = rule2_x + 1
    right_w = max(w - right_x, 1)

    left_panels = [Panel.Workspaces | ws.left]
    left = stack(left_panels, 0, left_w, body_h)
    right = stack(ws.right, right_x, right_w, body_h)
    {center_panel, _key} = ws.surface
    center = [{center_panel, %{x: center_x, y: 0, w: center_w, h: body_h}}]

    panels =
      (left ++ center ++ right)
      |> Enum.map(fn {panel, rect} -> {panel, data_for(panel, reads), rect} end)

    rules = [
      {Panel.Rule, nil, %{x: rule1_x, y: 0, w: 1, h: body_h}},
      {Panel.Rule, nil, %{x: rule2_x, y: 0, w: 1, h: body_h}}
    ]

    status = {Panel.StatusBar, status_data(reads, ws), %{x: 0, y: h - 1, w: w, h: 1}}

    panels ++ rules ++ [status]
  end

  @doc "Resolve the data a panel is fed from the assembled reads (keeps workspaces plain data)."
  def data_for(Panel.Workspaces, r), do: %{workspaces: Workspace.all(), active_key: r.active_key}
  def data_for(Panel.Roster, r), do: r.roster
  def data_for(Panel.ThreadList, r), do: %{threads: r.threads, selected_id: r.focused_id}
  def data_for(Panel.Dossier, r), do: r.scope
  def data_for(Panel.Conversation, r), do: %{title: r.focused_title, messages: r.chatter}
  def data_for(Panel.Session, r), do: r.session
  def data_for(_other, _r), do: nil

  defp status_data(reads, ws), do: %{workspace: ws.label, thread: reads.focused_title}

  # Stack panels vertically in a column: the picker takes a fixed height, the rest split the
  # remainder evenly (the last absorbs the rounding remainder so no row is left unpainted).
  defp stack([], _x, _w, _h), do: []

  defp stack(panels, x, w, total_h) do
    heights = split_heights(panels, total_h)

    {placed, _y} =
      Enum.zip(panels, heights)
      |> Enum.map_reduce(0, fn {panel, ph}, y ->
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

  # The picker is intrinsically short (header + one row per workspace); everything else flexes.
  defp fixed_height(Panel.Workspaces), do: length(Workspace.all()) + 3
  defp fixed_height(_panel), do: nil

  defp clamp_col(v, w), do: v |> max(@min_col) |> min(max(div(w, 3), @min_col))
end
