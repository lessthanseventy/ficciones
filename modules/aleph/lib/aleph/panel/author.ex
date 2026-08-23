defmodule Aleph.Panel.Author do
  @moduledoc """
  ORBIS' AUTHOR face: the editable funes-world list — create (`n`) and delete (`d`) from the LIST
  view (D2, Chunk 1); `e` on the cursor world opens the in-place FIELD EDITOR (D2.4 Chunk 2a),
  `data[:edit]` present. List: one row per `Aleph.Worlds.all/0` world (name · type · path/roster
  counts), the `author_cursor` row washed `:selected` — same wash idiom as
  `Aleph.Panel.Chorus`/`Leaves`. Data is `%{worlds: [%{id, name, type, paths, roster, scope}],
  cursor, edit}` (`cursor`/`edit` View-injected). Replaces Chorus as Orbis' center only while
  `orbis_face == :author` (`Aleph.View.compose/3`).

  The editor is a vertical 4-row field list (0 type · 1 scope · 2 paths · 3 roster), the `field`
  cursor washed `:selected`; fields 0/1 show the ring value inline (h/l cycles it, applied
  immediately — no draft/commit). `name` has no field — it's immutable
  (`Funes.World.edit_changeset` drops it), called out in the header instead. `Enter` on field 2/3
  (`edit.mode == :sub`) swaps in that field's sub-list — one row per path/roster entry, the `sub`
  cursor washed `:selected` — instead of the field list. Roster's sub-list is Chunk 2c.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  @hints "j/k row · n new · e edit · d delete · a survey"
  @edit_hints "j/k field · h/l cycle · Enter list · Esc back"
  @sub_hints "j/k row · a add · x/d remove · Esc back"

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.worlds_topic()]

  @impl Aleph.Panel
  def render(%{worlds: worlds} = data, rect) do
    case {Map.get(data, :edit), Enum.find(worlds, &(&1.id == data[:edit][:id]))} do
      {%{mode: :sub, field: 2} = edit, %{} = world} -> render_paths_sub(world, edit, rect)
      {%{} = edit, %{} = world} -> render_editor(world, edit, rect)
      _ -> render_list(worlds, Map.get(data, :cursor, 0), rect)
    end
  end

  defp render_list(worlds, cursor, rect) do
    header = [line("ORBIS · author", :header), blank()]

    body =
      case worlds do
        [] -> [line("no worlds yet — n to create one", :dim)]
        ws -> ws |> Enum.with_index() |> Enum.map(fn {w, i} -> world_row(w, i == cursor) end)
      end

    footer = [blank(), line(@hints, :dim)]

    Aleph.Panel.clip(header ++ body ++ footer, rect)
  end

  # Chunk 2a: the field list only (fields 0/1's rings). Chunk 2b/2c extend field 2/3's row with a
  # sub-list render when `edit.mode == :sub`.
  defp render_editor(world, edit, rect) do
    header = [
      line("ORBIS · author · edit", :header),
      [{Map.get(world, :name) || "?", :header}, {"  (name is immutable)", :dim}],
      blank()
    ]

    body = [
      field_row("type", Map.get(world, :type) || "?", edit.field == 0),
      field_row("scope", Map.get(world, :scope) || "?", edit.field == 1),
      field_row("paths", "#{length(Map.get(world, :paths) || [])} paths", edit.field == 2),
      field_row("roster", "#{length(Map.get(world, :roster) || [])} roster", edit.field == 3)
    ]

    footer = [blank(), line(@edit_hints, :dim)]

    Aleph.Panel.clip(header ++ body ++ footer, rect)
  end

  defp field_row(label, value, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    [gutter, {String.pad_trailing(label, 8), :dim}, {value, style}]
  end

  # Field 2's sub-list (D2.4 Chunk 2b): one row per path, the `sub` cursor washed :selected — same
  # gutter/wash idiom as the list/field views.
  defp render_paths_sub(world, edit, rect) do
    header = [line("ORBIS · author · edit · paths", :header), blank()]
    paths = Map.get(world, :paths) || []

    body =
      case paths do
        [] -> [line("no paths yet — a to add one", :dim)]
        ps -> ps |> Enum.with_index() |> Enum.map(fn {p, i} -> sub_row(p, i == edit.sub) end)
      end

    footer = [blank(), line(@sub_hints, :dim)]
    Aleph.Panel.clip(header ++ body ++ footer, rect)
  end

  defp sub_row(text, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    [gutter, {text, style}]
  end

  # No click target yet — the editor is keyboard-only (Chunk 2a/b/c). Kept as an explicit no-op
  # (not left unimplemented), same idiom as the list's pre-Chunk-2 pick/3.
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
