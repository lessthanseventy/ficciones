defmodule Aleph.Panel.Chorus do
  @moduledoc """
  ORBIS — the **survey**: Orbis' center, one row per WORLD (Slice 0: a single hardcoded world,
  Tlön). Each world row shows its name and the leads/open/stalled/done/trouble rollup for all its
  leaves — the god-view glance the operator opens on. `Enter` (keymap) or a click zooms to a
  world's lens (the Tlön space). Data is `%{worlds: [%{world, summary, leaves}]}` from
  `Aleph.Orbis.rollup/0`'s `worlds` key — an empty list when funes is down / there are no worlds.

  Was a per-thread message feed (`Funes.Channel.chorus/1`); re-pointed to worlds in the Slice 0
  collapse so the survey surveys worlds, not threads. The per-thread rollup still lives in the
  LEAVES sidebar (`Aleph.Panel.Leaves`), whose `summary_row/1` this reuses so the two never drift.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Aleph.Panel.Leaves

  # Header (title) + blank spacer above the world rows; each world block is head + summary + blank.
  @header_rows 2
  @world_rows 3

  # The cockpit already subscribes to ALL activity events, so the survey repaints on any thread's
  # activity — no per-thread topic needed.
  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{worlds: worlds}, rect) do
    header = [line("ORBIS · worlds", :header), blank()]

    body =
      case worlds do
        [] -> [line("no worlds yet", :dim)]
        ws -> Enum.flat_map(ws, &world_rows/1)
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a world's rows → zoom to its lens. Slice 0 has one world (Tlön), so any world row zooms
  # to the Tlön space; the header + blank (rows 0–1) and clicks past the last world are inert.
  @impl Aleph.Panel
  def pick(%{worlds: worlds} = data, _rect, local_y) do
    idx = Aleph.Panel.scroll_offset(data) + local_y - @header_rows
    world_at(worlds, idx)
  end

  def pick(_data, _rect, _local_y), do: nil

  # Slice 0: every world block is a fixed @world_rows tall, so idx→world is plain integer division.
  # Slice 1 (multi-world / wrapping summaries) must measure each block's rendered height instead.
  defp world_at(worlds, idx) when idx >= 0 do
    if div(idx, @world_rows) < length(worlds), do: {:switch_space, :tlon}
  end

  defp world_at(_worlds, _idx), do: nil

  # One world: a ▸ + its name, then an indented summary line — leaf count + the shared rollup line
  # (open/stalled/done, trouble called out only when there is any), then a blank spacer.
  defp world_rows(%{world: world, summary: summary, leaves: leaves}) do
    head = [{"▸ ", :accent}, {world, :header}]
    count = length(leaves)
    summary_line = [{"  #{count} #{leaf_word(count)} · ", :dim} | Leaves.summary_row(summary)]
    [head, summary_line, blank()]
  end

  defp leaf_word(1), do: "leaf"
  defp leaf_word(_n), do: "leaves"
end
