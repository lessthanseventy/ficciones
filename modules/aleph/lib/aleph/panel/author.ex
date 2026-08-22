defmodule Aleph.Panel.Author do
  @moduledoc """
  ORBIS' AUTHOR face (D2, Chunk 1): the editable funes-world list — create (`n`) and delete (`d`)
  here; the in-place field editor (type/paths/roster) is Chunk 2. One row per `Aleph.Worlds.all/0`
  world (name · type · path/roster counts), the `author_cursor` row washed `:selected` — same wash
  idiom as `Aleph.Panel.Chorus`/`Leaves`. Data is `%{worlds: [%{id, name, type, paths, roster,
  scope}], cursor}` (`cursor` View-injected, D2.2). Replaces Chorus as Orbis' center only while
  `orbis_face == :author` (`Aleph.View.compose/3`).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  @hints "j/k row · n new · d delete · a survey"

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.worlds_topic()]

  @impl Aleph.Panel
  def render(%{worlds: worlds} = data, rect) do
    cursor = Map.get(data, :cursor, 0)
    header = [line("ORBIS · author", :header), blank()]

    body =
      case worlds do
        [] -> [line("no worlds yet — n to create one", :dim)]
        ws -> ws |> Enum.with_index() |> Enum.map(fn {w, i} -> world_row(w, i == cursor) end)
      end

    footer = [blank(), line(@hints, :dim)]

    Aleph.Panel.clip(header ++ body ++ footer, rect)
  end

  # No editor yet (Chunk 2) — a click selects nothing right now. Kept as an explicit no-op (not
  # left unimplemented) so a future edit-on-click just fills this in, rather than adding pick/3
  # from scratch.
  @impl Aleph.Panel
  def pick(_data, _rect, _local_y), do: nil

  defp world_row(w, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    paths = Map.get(w, :paths) || []
    roster = Map.get(w, :roster) || []

    [
      gutter,
      {Map.get(w, :name) || "?", style},
      {"  ", :normal},
      {Map.get(w, :type) || "?", :dim},
      {"  ", :normal},
      {"#{length(paths)} paths", :dim},
      {" · ", :dim},
      {"#{length(roster)} roster", :dim}
    ]
  end
end
