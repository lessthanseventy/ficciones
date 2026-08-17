defmodule Aleph.Panel.Habits do
  @moduledoc """
  HABITS — how the machine should WORK with the operator (funes' habits axis): agent-PROPOSED,
  human-APPROVED working preferences, distinct from his stated constraints (his verbatim words).
  Lives on Tlön, the meta/machine lens — "how the machine works with Andrew" is a machine-wide
  concern, not a project's.

  Two sections: PENDING (the review queue — approve with `Funes.Dossier.approve_habit/1` from
  `mise run funes:console`) and APPROVED (the always-loaded set every session reads, served by
  `Funes.MCP.Resource.Habits`). Re-renders on the habits topic. A thin view over
  `Dossier.pending_habits/0` + `approved_habits/0`; data is `%{pending: [habit], approved: [habit]}`
  or nil.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.habits_topic()]

  @impl Aleph.Panel
  def render(nil, rect) do
    Aleph.Panel.clip([line("HABITS", :header), blank(), line("no habits yet", :dim)], rect)
  end

  def render(%{pending: pending, approved: approved}, rect) do
    rows =
      [line("HABITS", :header), blank()] ++
        section("PENDING (#{length(pending)})", Enum.map(pending, &pending_line/1), rect.w) ++
        section("APPROVED (#{length(approved)})", Enum.map(approved, &approved_line/1), rect.w)

    Aleph.Panel.clip(rows, rect)
  end

  # A pending habit awaiting review — marked ⋯, tagged with the agent that proposed it.
  defp pending_line(%{text: text, proposed_by: by}) when is_binary(by), do: "⋯ #{text} (#{by})"
  defp pending_line(%{text: text}), do: "⋯ #{text}"

  # An approved habit — part of the always-loaded set, marked ✓.
  defp approved_line(%{text: text}), do: "✓ #{text}"

  # A labelled section (label, its body bulleted + word-wrapped, then a blank spacer); an empty
  # body renders a dim "—" so the shape stays legible and honest — the section exists, it is
  # just empty, never an invented value. Mirrors Aleph.Panel.Dossier.
  defp section(label, [], w), do: section(label, ["—"], w)

  defp section(label, body, w) do
    body_rows =
      body
      |> Enum.flat_map(&Aleph.Text.wrap(&1, max(w - 2, 1)))
      |> Enum.map(fn text -> [{"  ", :dim}, {text, :normal}] end)

    [line(label, :label) | body_rows] ++ [blank()]
  end
end
