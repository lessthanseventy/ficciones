defmodule Aleph.Panel.Workline do
  @moduledoc """
  WORKLINES — the stage machine's own pane: one row per open workline, its current stage, a
  gate marker when parked awaiting the operator, and a ⚠ with the failing command when the
  latest verify check is red. Pure over `Funes.Workline.Ledger.statuses/0` — the SDLC loop's
  stage state made legible without a `funes:ledger` shell-out.

  Data is `%{worklines: [%{id, slug, title, stage, awaiting, blocking}], selected}` — `blocking`
  is `%{cmd, tail}` or `nil`. `nil` data (funes down) and `worklines: []` (nothing open) both
  render the same placeholder.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(nil, rect), do: Aleph.Panel.clip([line("no worklines", :dim)], rect)

  def render(%{worklines: []}, rect), do: Aleph.Panel.clip([line("no worklines", :dim)], rect)

  def render(%{worklines: worklines} = data, rect) do
    selected = Map.get(data, :selected)

    rows =
      worklines
      |> Enum.with_index()
      |> Enum.map(fn {w, i} -> workline_row(w, i == selected) end)

    Aleph.Panel.clip(rows, rect)
  end

  defp workline_row(%{slug: slug, stage: stage, awaiting: awaiting, blocking: blocking}, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: "▸ ", else: "  "

    gate = if awaiting, do: [{" ⏸ awaiting #{awaiting}", :label}], else: []
    warn = if blocking, do: [{" ⚠ #{blocking.cmd} — #{blocking.tail}", :warm}], else: []

    [{gutter, :dim}, {slug, style}, {" · ", :dim}, {stage, :accent}] ++ gate ++ warn
  end

  @impl Aleph.Panel
  def pick(%{worklines: worklines}, _rect, local_y) do
    case Enum.at(worklines, local_y) do
      %{id: id} -> {:focus_thread, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "worklines"}, {"⏎", "open"}]
end
