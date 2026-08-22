defmodule Aleph.Panel.Chorus do
  @moduledoc """
  ORBIS — the **survey**: Orbis' center, one row per WORLD. Each world row shows its name and the
  leads/open/stalled/done/trouble rollup for all its leaves — the god-view glance the operator
  opens on. `Enter` (keymap, `orbis_focus == :survey`) or a click zooms to the row's OWN world id
  (D0.2 — no more a single hardcoded lens). Data is `%{worlds: [%{id, name, summary, leaves}],
  survey_cursor, orbis_focus}` — `worlds` from `Aleph.Orbis.rollup/0`'s `worlds` key (an empty list
  when funes is down / there are no worlds); `survey_cursor`/`orbis_focus` (View-injected, D0.3)
  wash the cursor row `:selected`, only while the survey (not the thread list) has focus.

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
  def render(%{worlds: worlds} = data, rect) do
    header = [line("ORBIS · worlds", :header), blank()]
    # Only wash a row :selected while the SURVEY (not the thread list) has focus — D0.3.
    cursor = if Map.get(data, :orbis_focus) == :survey, do: Map.get(data, :survey_cursor)

    body =
      case worlds do
        [] -> [line("no worlds yet", :dim)]
        ws -> ws |> Enum.with_index() |> Enum.flat_map(fn {w, i} -> world_rows(w, i == cursor) end)
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a world's rows → zoom to ITS id (D0.2). The header + blank (rows 0–1) and clicks past
  # the last world are inert.
  @impl Aleph.Panel
  def pick(%{worlds: worlds} = data, _rect, local_y) do
    idx = Aleph.Panel.scroll_offset(data) + local_y - @header_rows
    world_at(worlds, idx)
  end

  def pick(_data, _rect, _local_y), do: nil

  # Every world block is a fixed @world_rows tall, so idx→world is plain integer division; a
  # wrapping/variable-height summary would need to measure each block's rendered height instead.
  defp world_at(worlds, idx) when idx >= 0 do
    case Enum.at(worlds, div(idx, @world_rows)) do
      %{id: id} -> {:switch_space, id}
      nil -> nil
    end
  end

  defp world_at(_worlds, _idx), do: nil

  # One world: a ▸ + its name (washed :selected under the survey cursor), then an indented summary
  # line — leaf count + the shared rollup line (open/stalled/done, trouble called out only when
  # there is any), then a blank spacer.
  defp world_rows(%{name: name, summary: summary, leaves: leaves}, selected?) do
    name_style = if selected?, do: :selected, else: :header
    head = [{"▸ ", :accent}, {name, name_style}]
    count = length(leaves)
    summary_line = [{"  #{count} #{leaf_word(count)} · ", :dim} | Leaves.summary_row(summary)]
    [head, summary_line, blank()]
  end

  defp leaf_word(1), do: "leaf"
  defp leaf_word(_n), do: "leaves"
end
