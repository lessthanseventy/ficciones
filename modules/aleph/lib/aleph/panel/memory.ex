defmodule Aleph.Panel.Memory do
  @moduledoc """
  MEMORY — what funes knows, closing the loop with the forgetting engine (design §Memory). A header
  of coverage stats over two navigable sections the focus cycles with `Tab`:

    * **FLOOR** — the always-loaded constraint facts (`Funes.floor/0`), pinned. `Enter` opens a
      fact's full text in MAIN.
    * **HABITS** — pending habits (`Funes.pending_habits/0`) as candidate constraints: `a` approves
      one into the floor, `r` rejects it. This is the write-path into memory.

  Data is `%{coverage, floor: [fact], habits: [habit], section, selected}` — `section` (0=floor,
  1=habits) and `selected` (the j/k cursor) are injected by the View only when this pane is focused,
  so an unfocused Memory shows the floor with no cursor. A thin view: no funes calls here.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0, rule: 1]

  alias Funes.Bus

  @floor_section 0
  @habits_section 1

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.habits_topic()]

  @impl Aleph.Panel
  def render(nil, rect), do: Aleph.Panel.clip([line("MEMORY", :header), blank(), line("no recall yet", :dim)], rect)

  def render(%{floor: floor, habits: habits} = data, rect) do
    section = Map.get(data, :section, @floor_section)
    selected = Map.get(data, :selected)

    rows =
      [line("MEMORY", :header)] ++
        coverage_rows(Map.get(data, :coverage)) ++
        [rule(rect.w)] ++
        floor_rows(floor, section == @floor_section, selected, rect.w) ++
        [blank()] ++
        habit_rows(habits, section == @habits_section, selected, rect.w)

    Aleph.Panel.clip(rows, rect)
  end

  # coverage: "embedded 30/30 · floor 8 ~1.1k/4k tok · N forgotten" — the corpus at a glance. A
  # forgotten count (facts not embedded, i.e. beyond recall) is derived from facts vs embedded.
  defp coverage_rows(nil), do: [blank()]

  defp coverage_rows(%{facts: facts, embedded: embedded, floor_count: fc, floor_tokens: ft, budget: budget}) do
    forgotten = max(facts - embedded, 0)

    [
      [
        {"  embedded ", :dim},
        {"#{embedded}/#{facts}", :normal},
        {" · floor ", :dim},
        {"#{fc}", :normal},
        {" ~#{tok(ft)}/#{tok(budget)}", :dim},
        {" · ", :dim},
        {"#{forgotten} forgotten", if(forgotten > 0, do: :warm, else: :dim)}
      ]
    ]
  end

  defp tok(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp tok(n), do: "#{n}"

  defp floor_rows(floor, active?, selected, w) do
    label = [{"FLOOR", section_style(active?)}, {" (#{length(floor)})", :dim}]

    body =
      case floor do
        [] -> [line("  —", :dim)]
        facts -> facts |> Enum.with_index() |> Enum.map(fn {f, i} -> fact_row(f, active? and i == selected, w) end)
      end

    [label | body]
  end

  defp habit_rows(habits, active?, selected, w) do
    hint = if active?, do: [{"  a", :accent}, {" approve  ", :dim}, {"r", :accent}, {" reject", :dim}], else: []
    label = [{"HABITS", section_style(active?)}, {" (#{length(habits)})", :dim}]

    body =
      case habits do
        [] -> [line("  —", :dim)]
        hs -> hs |> Enum.with_index() |> Enum.map(fn {h, i} -> habit_row(h, active? and i == selected, w) end)
      end

    [label | body] ++ [hint]
  end

  # The active section's label lights amber; the dormant one dims, so the eye knows where Tab landed.
  defp section_style(true), do: :label
  defp section_style(false), do: :dim

  defp fact_row(%{text: text}, selected?, w) do
    {gutter, style} = if selected?, do: {"▸ ", :selected}, else: {"  ", :normal}
    [{gutter <> truncate(text, w - 2), style}]
  end

  defp habit_row(%{text: text} = habit, selected?, w) do
    by = Map.get(habit, :proposed_by)
    tag = if is_binary(by), do: " (#{by})", else: ""
    {gutter, style} = if selected?, do: {"▸ ", :selected}, else: {"⋯ ", :dim}
    [{gutter <> truncate(text <> tag, w - 2), style}]
  end

  defp truncate(text, max) when max > 1 do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  defp truncate(text, _max), do: text
end
