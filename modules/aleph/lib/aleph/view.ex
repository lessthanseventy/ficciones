defmodule Aleph.View do
  @moduledoc """
  Composition: turn the cockpit's state into placed panels (design §3, "a view is plain data").
  Given the assembled funes `reads` and the terminal size, `compose/3` lays out the fixed frame —
  left sidebar (space picker + the active space's situational panels), the center surface, the
  right sidebar — each section in its own bordered box — and the status footer, as a list of
  `{panel, data, rect}` placements the `Aleph.Board` paints. Pure and testable: no TTY, no funes.

  `reads` is the map the Cockpit assembles:
    `%{active_key, focused_id, focused_title, roster, threads, scope, chatter, session}`
  """
  alias Aleph.Panel
  alias Aleph.Space

  @min_col 16
  # The bottom footer: an info line + a hints line (Aleph.Panel.StatusBar).
  @status_h 2
  # Below this width (phone / a shrunk tile) the three columns collapse to one (Addendum §D).
  @wide_min 80
  # Panels whose content can overflow their box and so accept a `:scroll` offset (wheel scroll).
  # The center Terminal, the Spaces picker (a fixed 3 rows), and StatusBar/Border never overflow.
  @scrollable [
    Panel.ThreadList,
    Panel.Chorus,
    Panel.Conversation,
    Panel.Dossier,
    Panel.Roster,
    Panel.Stack,
    Panel.Health,
    Panel.Logbook,
    Panel.Triage
  ]

  @spec compose(map(), pos_integer(), pos_integer()) :: [Aleph.Board.placement()]
  def compose(reads, w, h) do
    space = Space.fetch(reads.active_key)
    body_h = max(h - @status_h, 1)

    # Each column holds a stack of *sections*, each its own bordered box, so sections read as
    # defined regions. A section is a bare panel module (data resolved by `data_for/2`) or a
    # `{panel, read_key}` pair reading straight from `reads[key]` — how Tlön's two Terminal panes
    # get distinct data. Wide viewports get three columns; narrow ones collapse to one.
    columns =
      case layout_for(w) do
        :wide ->
          %{left: left, center: center, right: right} = wide_columns(w, body_h)

          [
            {left, [Panel.Spaces | space.left]},
            {center, space.surface},
            {right, space.right}
          ]

        :narrow ->
          sections = [Panel.Spaces | space.left] ++ space.surface ++ space.right
          [{%{x: 0, y: 0, w: w, h: body_h}, sections}]
      end

    boxes = Enum.flat_map(columns, fn {rect, panels} -> boxed(panels, rect) end)

    borders = Enum.map(boxes, fn {_section, rect} -> {Panel.Border, nil, rect} end)

    contents = Enum.map(boxes, fn {section, rect} -> content_for(section, reads, inset(rect)) end)

    status =
      {Panel.StatusBar, status_data(reads, space), %{x: 0, y: h - @status_h, w: w, h: @status_h}}

    # Borders first: panel content paints over each box interior, leaving only the frames.
    borders ++ contents ++ [status]
  end

  defp layout_for(w) when w >= @wide_min, do: :wide
  defp layout_for(_w), do: :narrow

  # The three-column geometry (left ¼ · center ½ · right ¼) of the wide layout, as box rects — the
  # single source of truth for where each column sits. `compose/3` places panels into these, and
  # `center_rect/2` derives the center Terminal's content rect from the SAME math, so the embedded
  # PTY can be sized to exactly what's on screen (a wider PTY spills pi past the frame; a shorter
  # one leaves a dead band).
  defp wide_columns(w, body_h) do
    left_w = clamp_col(div(w, 4), w)
    right_w = clamp_col(div(w, 4), w)
    center_w = max(w - left_w - right_w - 2, 1)
    center_x = left_w + 1
    right_x = center_x + center_w + 1
    right_w = max(w - right_x, 1)

    %{
      left: %{x: 0, y: 0, w: left_w, h: body_h},
      center: %{x: center_x, y: 0, w: center_w, h: body_h},
      right: %{x: right_x, y: 0, w: right_w, h: body_h}
    }
  end

  @doc """
  The content rect the center Terminal renders into for a `w`×`h` cockpit — the single source of
  truth the embedded PTY sizes to, so pi never draws wider or taller than the visible area. It is
  the wide layout's center column inset by its frame; the terminal-bearing spaces (Sessions, Tlön)
  each have a single-section center surface, so that box IS the full-height center column. (The PTY
  is only sized in the wide layout — a real cockpit is never below the narrow threshold.)
  """
  @spec center_rect(pos_integer(), pos_integer()) :: Panel.rect()
  def center_rect(w, h), do: inset(wide_columns(w, max(h - @status_h, 1)).center)

  # The content region inside a section box: one cell of frame + one of padding on each side.
  defp inset(%{x: x, y: y, w: w, h: h}) do
    %{x: x + 2, y: y + 1, w: max(w - 4, 1), h: max(h - 2, 1)}
  end

  # A keyed surface section reads its data directly; a bare module resolves via data_for/2.
  defp content_for({panel, read_key}, reads, rect), do: {panel, scroll_data(panel, reads[read_key], reads), rect}
  defp content_for(panel, reads, rect), do: {panel, scroll_data(panel, data_for(panel, reads), reads), rect}

  @doc "Resolve the data a panel is fed from the assembled reads (keeps spaces plain data)."
  def data_for(Panel.Spaces, r), do: %{spaces: Space.all(), active_key: r.active_key}
  def data_for(Panel.Roster, r), do: %{sessions: r.roster}

  def data_for(Panel.ThreadList, r), do: %{threads: r.threads, roster: r.roster, selected_id: r.focused_id}

  def data_for(Panel.Dossier, r), do: r.scope
  def data_for(Panel.Chorus, r), do: %{blocks: r.chorus, focused_id: r.focused_id}
  def data_for(Panel.Conversation, r), do: %{title: r.focused_title, messages: r.chatter}
  def data_for(Panel.Stack, r), do: r.stack
  def data_for(Panel.Health, r), do: r.health
  def data_for(Panel.Logbook, r), do: r.logbook
  def data_for(Panel.Triage, r), do: r.triage
  def data_for(Panel.Habits, r), do: r.habits
  def data_for(_other, _r), do: nil

  # Inject the panel's current scroll offset into scrollable panels' data (nil data left alone —
  # e.g. Dossier with no focused thread renders its placeholder, no scroll needed).
  defp scroll_data(_panel, nil, _reads), do: nil

  defp scroll_data(panel, data, reads) when panel in @scrollable,
    do: Map.put(data, :scroll, (reads[:scrolls] || %{})[panel] || 0)

  defp scroll_data(_panel, data, _reads), do: data

  defp status_data(reads, space) do
    %{
      space: space.label,
      thread: reads.focused_title,
      thread_count: length(reads.threads),
      live_count: Enum.count(reads.roster, & &1.warm?),
      # When the operator is typing a new-thread title, the footer becomes the prompt.
      input: reads[:input],
      # A transient result line (a spawn's pane id or failure), shown until the next keypress.
      flash: reads[:flash],
      # True for the one keypress after Ctrl+Space — the hints line shows the armed-prefix state.
      leader_pending?: reads[:leader_pending?]
    }
  end

  @gap 1

  # Stack sections vertically down a column as box rects, a 1-row gap between them. The picker
  # takes a fixed height, the rest split the remainder (the last absorbs the rounding remainder).
  defp boxed([], _rect), do: []

  defp boxed(panels, %{x: x, y: y, w: w, h: h}) do
    gaps = max(length(panels) - 1, 0) * @gap
    heights = split_heights(panels, max(h - gaps, length(panels)))

    {placed, _y} =
      panels
      |> Enum.zip(heights)
      |> Enum.map_reduce(y, fn {panel, ph}, cy ->
        {{panel, %{x: x, y: cy, w: w, h: ph}}, cy + ph + @gap}
      end)

    placed
  end

  defp split_heights(panels, total_h) do
    fixed = Enum.map(panels, &fixed_height/1)
    fixed_sum = fixed |> Enum.reject(&is_nil/1) |> Enum.sum()
    flex_count = Enum.count(fixed, &is_nil/1)
    flex = if flex_count > 0, do: max(div(total_h - fixed_sum, flex_count), 1), else: 0

    resolved = Enum.map(fixed, fn f -> f || flex end)
    # Hand any rounding remainder to the last panel so the column is fully used.
    used = Enum.sum(resolved)
    List.update_at(resolved, -1, &(&1 + max(total_h - used, 0)))
  end

  # The picker box is intrinsically short: header + blank + one row per space, plus its frame.
  defp fixed_height(Panel.Spaces), do: length(Space.all()) + 4
  defp fixed_height({panel, _read_key}), do: fixed_height(panel)
  defp fixed_height(_panel), do: nil

  defp clamp_col(v, w), do: v |> max(@min_col) |> min(max(div(w, 3), @min_col))
end
