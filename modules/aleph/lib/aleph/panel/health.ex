defmodule Aleph.Panel.Health do
  @moduledoc """
  HEALTH — the machine's always-on status: which services are up, disk and memory pressure,
  and the nix generation lag. Best-effort and honest: a probe that fails yields "?", never a
  crash. Re-rendered on every Cockpit tick (not Bus-driven — system state changes on a clock,
  not a topic).

  Data is `%{funes_up, tlon_up, nix_gen, nix_behind, disk_pct, mem_pct}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(data, rect) do
    header = [line("HEALTH", :header), blank()]
    body = rows(data)
    Aleph.Panel.clip(header ++ body, rect)
  end

  defp rows(data) do
    [
      row("funes :4040", data.funes_up),
      row("tlon tmux", data.tlon_up),
      nix_row(data.nix_gen, data.nix_behind),
      disk_row(data.disk_pct),
      mem_row(data.mem_pct)
    ]
  end

  defp row(label, true), do: [{"● ", :warm}, {label, :normal}]
  defp row(label, false), do: [{"○ ", :dim}, {label, :dim}]
  defp row(label, nil), do: [{"○ ", :dim}, {label <> " ?", :dim}]

  defp nix_row(nil, _), do: [{"○ ", :dim}, {"nix gen ?", :dim}]
  defp nix_row(gen, 0), do: [{"● ", :warm}, {"nix gen #{gen}", :normal}]
  defp nix_row(gen, behind) when behind > 0, do: [{"▲ ", :label}, {"nix gen #{gen} (#{behind} behind)", :normal}]
  defp nix_row(gen, _), do: [{"● ", :warm}, {"nix gen #{gen}", :normal}]

  defp disk_row(nil), do: [{"  disk ?", :dim}]
  defp disk_row(pct) when pct >= 90, do: [{"▲ ", :label}, {"disk #{pct}%", :normal}]
  defp disk_row(pct), do: [{"  disk #{pct}%", :dim}]

  defp mem_row(nil), do: [{"  mem ?", :dim}]
  defp mem_row(pct) when pct >= 90, do: [{"▲ ", :label}, {"mem #{pct}%", :normal}]
  defp mem_row(pct), do: [{"  mem #{pct}%", :dim}]
end
