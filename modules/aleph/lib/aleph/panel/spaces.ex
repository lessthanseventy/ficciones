defmodule Aleph.Panel.Spaces do
  @moduledoc """
  SPACES — the top-left picker for which lens is in the middle (design Addendum §B). Lists the
  spaces; the active one is highlighted. `Tab`/`Shift-Tab` cycles it. A pure view over
  `Aleph.Space.all/0`; no funes read, so no Bus topic.

  Data is `%{spaces: [%Aleph.Space{}], active_key: atom()}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0, pad: 3]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{spaces: spaces, active_key: active_key}, rect) do
    header = [line("SPACES", :header), blank()]
    body = Enum.map(spaces, &row(&1, &1.key == active_key, rect.w))
    Aleph.Panel.clip(header ++ body, rect)
  end

  defp row(space, true, w), do: pad([{"▸ ", :selected_accent}, {space.label, :selected_accent}], w, :selected)

  defp row(space, false, _w), do: [{"  ", :dim}, {space.label, :normal}]
end
