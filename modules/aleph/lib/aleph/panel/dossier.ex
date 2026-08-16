defmodule Aleph.Panel.Dossier do
  @moduledoc """
  IN SCOPE — the focused thread's brief (design §8), a thin view over `Funes.Board.in_scope/1`:
  NORTH STAR, LEAD, LEARNINGS, BLOCKERS (capped + a `more` count), SHIPPED, CHATTER. Re-renders
  on that thread's topic. Data is the `in_scope/1` map, or `nil` when nothing is focused.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]
  alias Funes.Bus

  @impl Aleph.Panel
  def topics(%{focused_id: id}) when not is_nil(id), do: [Bus.thread_topic(id)]
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(nil, rect) do
    Aleph.Panel.clip([line("IN SCOPE", :header), blank(), line("select a thread ↑↓", :dim)], rect)
  end

  def render(scope, rect) do
    rows =
      [line("IN SCOPE", :header), blank()] ++
        section("NORTH STAR", [scope.north_star], rect.w) ++
        lead_section(scope.lead, rect.w) ++
        section("LEARNINGS", capped_lines(scope.learnings, & &1.text), rect.w) ++
        section("BLOCKERS", capped_lines(scope.blockers, & &1.summary), rect.w) ++
        section("SHIPPED", capped_lines(scope.shipped, &shipped_line/1), rect.w) ++
        section("CHATTER", Enum.map(scope.chatter, &chatter_line/1), rect.w)

    Aleph.Panel.clip(rows, rect)
  end

  defp lead_section(nil, w), do: section("LEAD", ["unassigned"], w)
  defp lead_section(name, w), do: section("LEAD", [name], w)

  # A capped section (%{shown, more}, funes Board): the cut is always rendered
  # WITH its count — a cut without a count lies.
  defp capped_lines(%{shown: [], more: _}, _fmt), do: []

  defp capped_lines(%{shown: shown, more: more}, fmt) do
    Enum.map(shown, fmt) ++ if(more > 0, do: ["+#{more} more"], else: [])
  end

  defp shipped_line(%{detail: detail}) when is_map(detail),
    do: Map.get(detail, "summary") || "work landed"

  defp shipped_line(_event), do: "work landed"

  defp chatter_line(%{author: author, body: body}), do: "#{author}: #{body}"

  # A labelled section: the label, its body word-wrapped and bulleted, then a blank spacer.
  # An empty body renders a dim "—" so the shape of the brief stays legible (and honest: the
  # section exists, it is just empty — never an invented value).
  defp section(label, [], w), do: section(label, ["—"], w)

  defp section(label, body, w) do
    body_rows =
      body
      |> Enum.flat_map(&Aleph.Text.wrap(&1, max(w - 2, 1)))
      |> Enum.map(fn text -> [{"  ", :dim}, {text, :normal}] end)

    [line(label, :label) | body_rows] ++ [blank()]
  end
end
