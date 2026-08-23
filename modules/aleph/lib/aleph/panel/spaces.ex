defmodule Aleph.Panel.Spaces do
  @moduledoc """
  SPACES — the top-left picker for which lens is in the middle (design Addendum §B). Lists the
  spaces; the active one carries the `▸` highlight. `Tab`/`Shift-Tab` cycles it, and in Tlön nav
  mode the focus SM can land here (`h`/`H`) — `selected` then marks the `j/k` cursor with a `→`
  accent so you see where `Enter` would switch, distinct from the currently-active lens. A pure view
  over `Aleph.Space.all/0`; no funes read, so no Bus topic.

  Data is `%{spaces: [%Aleph.Space{}], active_key: atom()}`, plus `selected` (the nav cursor index)
  only while this pane holds the Tlön focus.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [pad: 3]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{spaces: spaces, active_key: active_key} = data, rect) do
    cursor = data[:selected]

    body =
      spaces
      |> Enum.with_index()
      |> Enum.map(fn {space, i} -> row(space, space.key == active_key, i == cursor, rect.w) end)

    Aleph.Panel.clip(body, rect)
  end

  # Click a space row → switch to it. Rows start at 0 (title now lives on the frame).
  @impl Aleph.Panel
  def pick(%{spaces: spaces}, _rect, local_y) do
    spaces |> Enum.at(local_y) |> switch_space()
  end

  defp switch_space(nil), do: nil
  defp switch_space(%{key: key}), do: {:switch_space, key}

  # The active lens: the solid ▸ highlight, cursor or not.
  defp row(space, true, _cursor?, w), do: pad([{"▸ ", :selected_accent}, {space.label, :selected_accent}], w, :selected)

  # The nav cursor sits on a non-active lens: an accent → marks where Enter would switch.
  defp row(space, false, true, _w), do: [{"→ ", :accent}, {space.label, :accent}]

  defp row(space, false, false, _w), do: [{"  ", :dim}, {space.label, :normal}]

  @impl Aleph.Panel
  def hints(_data), do: [{"j/k", "spaces"}, {"⏎", "switch"}]
end
