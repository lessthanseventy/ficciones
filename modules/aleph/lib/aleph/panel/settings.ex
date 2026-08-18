defmodule Aleph.Panel.Settings do
  @moduledoc """
  SETTINGS — the operator's in-app knobs (Tlön, under the Stack): today the coworker's driver
  model, cycled with the `m` verb ((leader) m from inside the terminal) through
  `Aleph.Profiles.model_ring/0` and persisted by `Aleph.Config`. A change applies on the next
  coworker spawn (`aleph:reset` then re-enter Tlön), and the panel says so — no silent lies about
  the running session. More knobs land here as they earn a UI (thinking level, spawn agent, …).

  Data is `%{profile, model, ring, override?}` — `model` the EFFECTIVE driver (override merged),
  `override?` whether it came from the settings file rather than the compiled default.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(nil, _rect), do: []

  def render(data, rect) do
    header = [line("SETTINGS", :header), blank()]
    Aleph.Panel.clip(header ++ coworker_rows(data), rect)
  end

  defp coworker_rows(%{profile: profile, model: model, ring: ring} = data) do
    [
      [{"coworker ", :label}, {profile, :normal}],
      [{"  driver ", :dim}, {format_model(model), :normal}, {source_tag(data), :dim}],
      line("  m cycles · applies on respawn", :dim),
      blank()
    ] ++ ring_rows(ring, model)
  end

  # The ring, current entry marked — the operator sees what `m` will do before pressing it.
  defp ring_rows(ring, current) do
    Enum.map(ring, fn entry ->
      if entry.provider == current[:provider] and entry.model == current[:model] do
        [{"● ", :warm}, {format_model(entry), :normal}]
      else
        [{"○ ", :dim}, {format_model(entry), :dim}]
      end
    end)
  end

  defp format_model(%{provider: prov, model: model}), do: "#{prov}/#{model}"
  defp format_model(_), do: "base default"

  defp source_tag(%{override?: true}), do: " (set here)"
  defp source_tag(_), do: ""
end
