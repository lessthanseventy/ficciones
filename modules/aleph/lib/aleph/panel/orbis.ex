defmodule Aleph.Panel.Orbis do
  @moduledoc """
  ORBIS — the machine-scoped **rollup lens** (Orbis Tertius design, slice 2): a compact vantage over
  the Tlön leaf threads, rendered on Tlön in the slot Logbook used to hold. Where the `chat` tab is
  the full machine chorus (every leaf's feed), this is the glance-value summary the operator reads
  from the main cockpit without switching tabs: a header count line (open / stalled / done, with
  conflicts called out) then one row per leaf — its lead and status, with a stalled leaf surfacing
  its conflict count so trouble is visible without drilling in.

  Data is `%{summary: %{open, stalled, done, conflicts}, rows: [%{id, title, lead, status, conflicts}]}`
  — where `status` is `:open | :stalled | :done` — or `nil` when funes is down / there are no machine
  threads. Pure over that read (gathered by `Aleph.Cockpit.orbis_read/1` from `Funes.Board`), so the
  whole render path is headlessly testable, the same boundary the other panels draw.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  # The header chrome above the leaf rows: title, blank, the rollup line, blank.
  @header_rows 4

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(nil, rect) do
    Aleph.Panel.clip([line("ORBIS", :header), blank(), line("no machine threads", :dim)], rect)
  end

  def render(%{summary: summary, rows: rows}, rect) do
    header = [line("ORBIS", :header), blank(), summary_row(summary), blank()]
    body = if rows == [], do: [line("all clear", :dim)], else: Enum.map(rows, &leaf_row(&1, rect.w))
    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a leaf row → focus that thread (so composing targets it). The header rows are inert.
  @impl Aleph.Panel
  def pick(%{rows: rows}, _rect, local_y) do
    case Enum.at(rows, local_y - @header_rows) do
      %{id: id} when local_y >= @header_rows -> {:focus_thread, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

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

  # One leaf: a status glyph, the title, and the lead; a stalled leaf trails its conflict count.
  defp leaf_row(%{title: title, lead: lead, status: status} = row, _w) do
    {glyph, style} = status_glyph(status)
    who = if lead && lead != "", do: lead, else: "?"

    base = [{glyph, style}, {title || "untitled", :normal}, {" · ", :dim}, {who, :accent}]

    case {status, row[:conflicts] || 0} do
      {:stalled, n} when n > 0 -> base ++ [{" · ", :dim}, {"#{n}⚠", :label}]
      _ -> base
    end
  end

  defp status_glyph(:stalled), do: {"▲ ", :label}
  defp status_glyph(:done), do: {"✓ ", :dim}
  defp status_glyph(_open), do: {"▸ ", :accent}
end
