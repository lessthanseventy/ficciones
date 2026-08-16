defmodule Aleph.Panel.Workspaces do
  @moduledoc """
  WORKSPACES — the top-left picker for *what's in the middle* (design §3, the Herdr layer rebuilt
  clean). Lists the workspaces; the active one is highlighted. `Tab`/`Shift-Tab` cycles it. A
  pure view over `Aleph.Workspace.all/0`; no funes read, so no Bus topic.

  Data is `%{workspaces: [%Aleph.Workspace{}], active_key: atom()}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0, pad: 3]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{workspaces: workspaces, active_key: active_key}, rect) do
    header = [line("WORKSPACES", :header), blank()]
    body = Enum.map(workspaces, &row(&1, &1.key == active_key, rect.w))
    Aleph.Panel.clip(header ++ body, rect)
  end

  defp row(ws, true, w),
    do: pad([{"▸ ", :selected_accent}, {ws.label, :selected_accent}], w, :selected)

  defp row(ws, false, _w), do: [{"  ", :dim}, {ws.label, :normal}]
end
