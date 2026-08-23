defmodule Aleph.MachineChat.Crew do
  @moduledoc """
  The right CREW rail — the coworker pool at a glance: who exists (the world roster), what each
  one is (archetype · model · harness), whether it's working right now (tmux activity via
  `Aleph.MachineChat.Presence`), and where (its standing seat or the leaf it leads). Pure rows
  from pre-assembled data `%{coworkers: [%{name, archetype, model, harness, status, seat}],
  leaves: {live, cap}}` — the loop assembles, this renders.
  """

  import Aleph.Panel, only: [blank: 0]

  @doc "The crew panel's rows."
  @spec render(map(), map()) :: [[{String.t(), term()}]]
  def render(%{coworkers: coworkers, leaves: {live, cap}}, rect) do
    header = [[{"CREW", :header}, {"  leaves #{live}/#{cap}", :dim}], blank()]
    header ++ Enum.flat_map(coworkers, &entry(&1, rect.w))
  end

  defp entry(cw, w) do
    {glyph, label} = presence(cw.status)

    [
      [{clip("#{cw.name}", w - 12), :normal}, {"  #{cw.archetype}", :dim}],
      [{"  #{glyph} ", glyph_style(cw.status)}, {clip(label <> seat(cw), w - 4), :dim}],
      [{clip("  #{short_model(cw.model)} · #{harness_label(cw.harness)}", w), :dim}],
      blank()
    ]
  end

  defp presence(:working), do: {"●", "working"}
  defp presence(:live), do: {"●", "idle"}
  defp presence(:none), do: {"○", "off"}

  defp glyph_style(:working), do: :accent
  defp glyph_style(_status), do: :dim

  defp seat(%{status: :none}), do: ""
  defp seat(%{seat: nil}), do: ""
  defp seat(%{seat: title}), do: " · #{title}"

  defp harness_label(:claude_code), do: "claude"
  defp harness_label(other), do: to_string(other)

  defp short_model(nil), do: "base"
  defp short_model(%{model: m}), do: m
  defp short_model(m) when is_binary(m), do: m

  defp clip(_text, max) when max < 1, do: ""

  defp clip(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
