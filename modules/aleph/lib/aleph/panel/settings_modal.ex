defmodule Aleph.Panel.SettingsModal do
  @moduledoc """
  The Tlön settings modal's body (design: `docs/plans/2026-08-20-tlon-lazygit-panels-design.md`
  §Settings) — a key-invoked overlay, not an always-on pane, per the "monitor vs. act" principle.
  Each coworker profile aleph materialises gets a row: its effective driver model (with the ring
  the model knob cycles) and its permission policy (yolo/ask). `,` opens it, `j/k` pick the row,
  `Tab`/`h`/`l` flip which knob is selected, `Enter`/`Space` applies — the `Aleph.Tlon.Settings`
  reducer holds that selection; this only draws it.

  Data is `%{row, field, rows: [%{profile, model, ring, override?, yolo?}]}` — `row`/`field` the
  selection (which coworker, `:model` | `:permission`), each row the read for one coworker. A change
  is honest-scoped: it persists via `Aleph.Config` and applies on the coworker's next spawn.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @doc "The content height (rows) this data renders to — the View sizes the centered box to it."
  @spec height(map()) :: pos_integer()
  def height(data), do: length(content_rows(data))

  @impl Aleph.Panel
  def render(nil, _rect), do: []
  def render(data, rect), do: Aleph.Panel.clip(content_rows(data), rect)

  defp content_rows(%{rows: rows, row: sel_row, field: field}) do
    header = [line("SETTINGS — coworker driver + permissions", :header), blank()]

    body =
      rows
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, i} -> coworker_block(row, i == sel_row, field) end)

    footer = [blank(), line("j/k row · Tab knob · Enter apply · , close", :dim)]
    header ++ body ++ footer
  end

  # One coworker's block: name, the model knob (ring below it), the permission knob. The SELECTED
  # knob on the selected row gets a ▸ marker + accent — the cue for what Enter will change.
  defp coworker_block(%{profile: name, model: model} = row, selected?, field) do
    name_style = if selected?, do: :warm, else: :label

    [
      [{"● ", name_style}, {name, name_style}],
      knob_line("driver", format_model(model) <> source_tag(row), selected? and field == :model)
    ] ++
      ring_rows(row.ring, model, selected? and field == :model) ++
      [
        knob_line("perms ", yolo_label(row[:yolo?]), selected? and field == :permission),
        blank()
      ]
  end

  defp knob_line(label, value, active?) do
    if active?,
      do: [{"  ▸ ", :accent}, {label <> " ", :accent}, {value, :normal}],
      else: [{"    ", :dim}, {label <> " ", :dim}, {value, :normal}]
  end

  # The model ring, current entry marked; dimmer than the knob lines so it reads as the menu the
  # driver knob cycles, not a second control.
  defp ring_rows(ring, current, _active?) do
    Enum.map(ring, fn entry ->
      if entry.provider == current[:provider] and entry.model == current[:model],
        do: [{"      ● ", :warm}, {format_model(entry), :normal}],
        else: [{"      ○ ", :dim}, {format_model(entry), :dim}]
    end)
  end

  defp format_model(%{provider: prov, model: model}), do: "#{prov}/#{model}"
  defp format_model(_), do: "base default"

  defp source_tag(%{override?: true}), do: " (set here)"
  defp source_tag(_), do: ""

  defp yolo_label(true), do: "yolo (auto-approve asks)"
  defp yolo_label(false), do: "ask (human answers)"
  defp yolo_label(_), do: "—"
end
