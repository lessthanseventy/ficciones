defmodule Aleph.Panel.Leaves do
  @moduledoc """
  LEAVES — the machine-scoped **rollup lens** over Tlön's leaf threads (was `Panel.Orbis`, renamed
  so it stops colliding with the Orbis *space*). A header count line (open / stalled / done, with
  conflicts called out) then one row per leaf — its lead and status, a stalled leaf surfacing its
  conflict count. The glance-value summary the operator reads without switching to the chat tab.

  Navigable in Tlön nav mode: `j/k` selects a leaf (the cursor row washes :selected), `Enter`
  attaches that leaf in the World center — re-points the tmux window (Slice 0 collapse; was a jump
  into the now-deleted Sessions space); its own `t<id>` window if live, else its lead's (C3.3). Data
  is `%{summary: %{open, stalled, done, conflicts}, rows: [%{id, title, lead, status, conflicts}],
  selected, attached}` — `selected` (cursor) and `attached` (the leaf whose own window IS the
  center, persistent) both injected by the View, either `nil`; either washes the row :selected — or
  `nil` when funes is down / there are no machine threads. Pure over `Aleph.Orbis.rollup/0`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  # The header chrome above the leaf rows: the rollup line, blank (title now lives on the frame).
  @header_rows 2

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(nil, rect) do
    Aleph.Panel.clip([line("no machine threads", :dim)], rect)
  end

  def render(%{summary: summary, rows: rows} = data, rect) do
    selected = Map.get(data, :selected)
    attached = Map.get(data, :attached)
    rows = ordered(rows, Map.get(data, :focused_lead))
    header = [summary_row(summary), blank()]

    body =
      if rows == [],
        do: [line("all clear", :dim)],
        else:
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, i} -> leaf_row(row, i == selected or row.id == attached, rect.w) end)

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a leaf row → focus that thread (so composing targets it). The header rows are inert.
  # Uses the SAME `ordered/2` as render so a click lands on the row the operator sees (C3.2).
  @impl Aleph.Panel
  def pick(%{rows: rows} = data, _rect, local_y) do
    case Enum.at(ordered(rows, Map.get(data, :focused_lead)), local_y - @header_rows) do
      %{id: id} when local_y >= @header_rows -> {:focus_thread, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  # C3.2: float the focused leader's leaves to the top, stable within each group (split_with keeps
  # source order), so the active leader owns the top of the panel. `focused_lead` = the active
  # WindowBar tab's agent handle, injected by the View; nil (no leader active) → source order.
  defp ordered(rows, nil), do: rows

  defp ordered(rows, focused_lead) do
    {mine, others} = Enum.split_with(rows, &(&1.lead == focused_lead))
    mine ++ others
  end

  @doc """
  The rollup line as a styled row: the operator's three buckets, conflicts appended only when there
  are any — a clean board reads clean, and a cut without a count would be its own little lie. Public
  so the `chat` tab's header strip (`Aleph.MachineChat.Loop`) paints the identical line above its
  feed, not a hand-rolled copy that could drift.
  """
  @spec summary_row(map()) :: Aleph.Panel.row()
  def summary_row(%{open: open, stalled: stalled, done: done} = summary) do
    base = [
      {"#{open} open", :normal},
      {" · ", :dim},
      {"#{stalled} stalled", stalled_style(stalled)},
      {" · ", :dim},
      {"#{done} done", :dim}
    ]

    case summary[:conflicts] || 0 do
      0 -> base
      n -> base ++ [{" · ", :dim}, {"#{n} conflicts", :label}]
    end
  end

  defp stalled_style(0), do: :normal
  defp stalled_style(_n), do: :label

  # One leaf: a status glyph, the title, and the lead; a stalled leaf trails its conflict count. The
  # selected leaf (j/k) washes :selected so the eye lands on which Enter would jump to.
  defp leaf_row(%{title: title, lead: lead, status: status} = row, selected?, _w) do
    {glyph, glyph_style} = status_glyph(status)
    who = if lead && lead != "", do: lead, else: "?"
    title_style = if selected?, do: :selected, else: :normal

    base = [{glyph, glyph_style}, {title || "untitled", title_style}, {" · ", :dim}, {who, :accent}]

    case {status, row[:conflicts] || 0} do
      {:stalled, n} when n > 0 -> base ++ [{" · ", :dim}, {"#{n}⚠", :label}]
      _ -> base
    end
  end

  defp status_glyph(:stalled), do: {"▲ ", :label}
  defp status_glyph(:done), do: {"✓ ", :dim}
  defp status_glyph(_open), do: {"▸ ", :accent}

  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "leaves"}, {"⏎", "attach"}, {"y", "title"}]

  @doc "The semantic yank for the cursor row: the leaf title, same float order as render/pick."
  def yank(%{rows: rows} = data, cursor) do
    case Enum.at(ordered(rows, Map.get(data, :focused_lead)), cursor) do
      %{title: title} when is_binary(title) -> {"title", title}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil
end
