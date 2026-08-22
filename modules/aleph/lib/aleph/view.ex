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
  alias Aleph.Mention
  alias Aleph.Panel
  alias Aleph.Space
  alias Aleph.Tlon.Focus
  alias Funes.Presence

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
    Panel.Leaves,
    Panel.Activity,
    Panel.Triage,
    Panel.Settings,
    Panel.Memory,
    Panel.Detail
  ]

  @spec compose(map(), pos_integer(), pos_integer()) :: [Aleph.Board.placement()]
  def compose(reads, w, h) do
    space = fetch_space(reads.active_key)
    body_h = max(h - @status_h, 1)

    # Each column holds a stack of *sections*, each its own bordered box, so sections read as
    # defined regions. A section is a bare panel module (data resolved by `data_for/2`) or a
    # `{panel, read_key}` pair reading straight from `reads[key]` — how Tlön's two Terminal panes
    # get distinct data. Wide viewports get three columns; narrow ones collapse to one.
    # MAIN is the terminal by default; a Tlön focus that opened a detail (Enter) replaces it with
    # the Detail panel until Esc closes it (the tmux terminal keeps running underneath, unpainted).
    center_panels = if detail_open?(reads), do: [Panel.Detail], else: space.surface

    columns =
      case layout_for(w) do
        :wide ->
          %{left: left, center: center, right: right} = wide_columns(w, body_h)

          [
            {left, [Panel.Spaces | space.left]},
            {center, center_panels},
            {right, space.right}
          ]

        :narrow ->
          sections = [Panel.Spaces | space.left] ++ center_panels ++ space.right
          [{%{x: 0, y: 0, w: w, h: body_h}, sections}]
      end

    boxes = Enum.flat_map(columns, fn {rect, panels} -> boxed(panels, rect) end)

    # In Tlön nav mode one sidebar pane is focused — its border lights up (the lazygit "active
    # pane" cue). Every other box, and every other space, stays neutral.
    focused = focused_section(reads[:focus], space)
    borders = Enum.map(boxes, fn {section, rect} -> {Panel.Border, border_data(section, focused), rect} end)

    # The focused pane alone is fed a slice of the focus — its item cursor (j/k) as `selected` and
    # the active `section` (Tab) — so it lights the row Enter would open and the section Tab landed
    # on; every other pane gets nil (no selection, default section).
    slice = focus_slice(reads)

    contents =
      Enum.map(boxes, fn {section, rect} ->
        content_for(section, reads, inset(rect), if(section == focused, do: slice))
      end)

    status =
      {Panel.StatusBar, status_data(reads, space), %{x: 0, y: h - @status_h, w: w, h: @status_h}}

    # Borders first: panel content paints over each box interior, leaving only the frames. The
    # settings modal (if open) is appended LAST so its opaque box paints over everything — a
    # floating overlay, not a column swap (the tmux terminal keeps running underneath, unpainted).
    borders ++ contents ++ [status] ++ modal_placements(reads, w, h)
  end

  # The centered settings-modal overlay: a filled Border box + the modal body inset inside it. []
  # when closed (reads.modal nil). Sized to the content height, capped to the viewport.
  defp modal_placements(%{modal: %{} = modal}, w, h) do
    mw = min(60, max(w - 4, 1))
    mh = min(Panel.SettingsModal.height(modal) + 2, max(h - 2, 1))
    rect = %{x: div(w - mw, 2), y: div(h - mh, 2), w: mw, h: mh}
    [{Panel.Border, %{focused: true}, rect}, {Panel.SettingsModal, modal, inset(rect)}]
  end

  defp modal_placements(_reads, _w, _h), do: []

  defp layout_for(w) when w >= @wide_min, do: :wide
  defp layout_for(_w), do: :narrow

  # The sidebar pane the Tlön focus sits on — only in nav mode (out of the terminal), so the frame
  # lights the instant you Ctrl+Space out. nil for other spaces and while in the terminal (the
  # terminal is the active pane then). Matches by section module — the panes are distinct, so module
  # identity is unambiguous. SPACES leads the left column here exactly as it does on screen, so its
  # frame lights when the focus navigates onto the space-switcher.
  defp focused_section(%Focus{in_terminal?: false} = focus, space),
    do: Focus.focused_pane(focus, %{left: [Panel.Spaces | space.left], right: space.right, sections: %{}})

  defp focused_section(_focus, _space), do: nil

  defp border_data(section, focused) when not is_nil(focused) and section == focused, do: %{focused: true}
  defp border_data(_section, _focused), do: nil

  # True when the Tlön focus has a detail open AND the cockpit resolved content for it — an Enter on
  # a pane with no detail (nil) leaves the terminal in place rather than blanking MAIN.
  defp detail_open?(%{focus: %Focus{detail?: true}} = reads), do: reads[:detail] != nil
  defp detail_open?(_reads), do: false

  # The slice of the focus the focused pane needs to render: `selected` (the clamped j/k cursor) and
  # the active `section` (Tab). nil outside Tlön nav — panes then render their default (section 0,
  # no selection).
  defp focus_slice(%{focus: %Focus{} = focus, tlon_layout: layout}) when is_map(layout),
    do: %{selected: Focus.cursor(focus, layout), section: focus.section}

  defp focus_slice(_reads), do: nil

  # The three-column geometry (left ¼ · center ½ · right ¼) of the wide layout, as box rects — the
  # single source of truth for where each column sits. `compose/3` places panels into these, and
  # `center_rect/3` derives the center Terminal's content rect from the SAME math, so the embedded
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
  The content rect the center Terminal renders into for a `space_key`/`w`×`h` cockpit — the single
  source of truth the embedded PTY sizes to, so pi never draws wider or taller than the visible
  area. Orbis carries no center Terminal (its surface is `[Chorus]`, the survey) → this falls back
  to the full center column. Tlön's WindowBar/Pulse bands (`Aleph.Space`) share the column with its
  Terminal, so its box is smaller — found via the SAME `boxed/2` stacking `compose/3` uses, not a
  second formula that could drift. (The PTY is only sized in the wide layout — a real cockpit is
  never below the narrow threshold.)
  """
  @spec center_rect(atom(), pos_integer(), pos_integer()) :: Panel.rect()
  def center_rect(space_key, w, h) do
    center_col = wide_columns(w, max(h - @status_h, 1)).center
    surface = fetch_space(space_key).surface

    case Enum.find(boxed(surface, center_col), &terminal_section?/1) do
      {_section, rect} -> inset(rect)
      nil -> inset(center_col)
    end
  end

  # `Space.fetch/1` returns nil on a miss (Phase C1: no silent Orbis default at the Space layer) —
  # a stale/unknown active_key mid-render degrades to an empty space here instead of crashing the
  # paint (View chooses to be forgiving; Space stays honest).
  defp fetch_space(key), do: Space.fetch(key) || %Space{key: key, label: "?", surface: []}

  defp terminal_section?({Panel.Terminal, _rect}), do: true
  defp terminal_section?({{Panel.Terminal, _read_key}, _rect}), do: true
  defp terminal_section?(_boxed), do: false

  # The content region inside a section box: one cell of frame + one of padding on each side.
  defp inset(%{x: x, y: y, w: w, h: h}) do
    %{x: x + 2, y: y + 1, w: max(w - 4, 1), h: max(h - 2, 1)}
  end

  # A keyed surface section reads its data directly; a bare module resolves via data_for/2. The
  # 4-arity variant injects the focused pane's `selected` cursor into its data (nil elsewhere).
  defp content_for(section, reads, rect, slice) do
    {panel, data, rect} = content_for(section, reads, rect)
    {panel, merge_slice(data, slice), rect}
  end

  defp content_for({panel, read_key}, reads, rect), do: {panel, scroll_data(panel, reads[read_key], reads), rect}
  defp content_for(panel, reads, rect), do: {panel, scroll_data(panel, data_for(panel, reads), reads), rect}

  defp merge_slice(data, nil), do: data
  defp merge_slice(data, slice) when is_map(data), do: Map.merge(data, slice)
  defp merge_slice(data, _slice), do: data

  @doc "Resolve the data a panel is fed from the assembled reads (keeps spaces plain data)."
  def data_for(Panel.Spaces, r), do: %{spaces: Space.all(), active_key: r.active_key}
  def data_for(Panel.Roster, r), do: %{sessions: r.roster}

  def data_for(Panel.ThreadList, r), do: %{threads: r.threads, roster: r.roster, selected_id: r.focused_id}

  def data_for(Panel.Dossier, r), do: r.scope
  def data_for(Panel.Chorus, r), do: %{worlds: r[:worlds] || []}
  def data_for(Panel.Conversation, r), do: %{title: r.focused_title, messages: r.chatter}
  def data_for(Panel.Stack, r), do: r.stack
  def data_for(Panel.Health, r), do: r.health
  def data_for(Panel.Logbook, r), do: r.logbook
  def data_for(Panel.Leaves, r), do: with_focused_lead(r.orbis, r)
  def data_for(Panel.Activity, r), do: %{events: r[:activity] || []}
  def data_for(Panel.Pulse, r), do: %{events: r[:activity] || []}
  def data_for(Panel.WindowBar, r), do: %{tabs: window_tabs(r), engine: engine_state(), thread: r.focused_id}
  def data_for(Panel.Triage, r), do: r.triage
  def data_for(Panel.Habits, r), do: r.habits
  def data_for(Panel.Settings, r), do: r.settings
  def data_for(Panel.Memory, r), do: r[:memory]
  def data_for(Panel.Detail, r), do: r[:detail]
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
      leader_pending?: reads[:leader_pending?],
      # Tlön's focus (nil elsewhere) — the footer shows NAV/TERM and the focus-model hints.
      focus: reads[:focus]
    }
  end

  @gap 1

  # Stack sections vertically down a column as box rects, a 1-row gap between them. The picker
  # takes a fixed height, the rest split the remainder (the last absorbs the rounding remainder).
  defp boxed([], _rect), do: []

  defp boxed(panels, %{x: x, y: y, w: w, h: h}) do
    gaps = max(length(panels) - 1, 0) * @gap
    # The section budget is the column minus the inter-section gaps; never inflate it past what
    # fits (a `length(panels)` floor would push short columns off-frame). split_heights/2 fits the
    # sections into exactly this budget, so no placed box's `y + h` ever exceeds the column bottom.
    heights = split_heights(panels, max(h - gaps, 0))

    {placed, _y} =
      panels
      |> Enum.zip(heights)
      |> Enum.map_reduce(y, fn {panel, ph}, cy ->
        {{panel, %{x: x, y: cy, w: w, h: ph}}, cy + ph + @gap}
      end)

    placed
  end

  # Resolve each section's height within `total_h` (the column's row budget net of gaps). The
  # invariant is that the resolved heights SUM to at most `total_h`, so `boxed/2` never places a box
  # past the column bottom (design: "no overflow past the frame").
  defp split_heights(panels, total_h) do
    fixed = Enum.map(panels, &fixed_height/1)
    fixed_sum = fixed |> Enum.reject(&is_nil/1) |> Enum.sum()
    flex_count = Enum.count(fixed, &is_nil/1)

    if fixed_sum <= total_h do
      # Room for every fixed section at nominal height: the flex sections split the remainder, and
      # any rounding leftover goes to the last section so the column is fully used.
      flex = if flex_count > 0, do: max(div(total_h - fixed_sum, flex_count), 0), else: 0
      resolved = Enum.map(fixed, fn f -> f || flex end)
      used = Enum.sum(resolved)
      List.update_at(resolved, -1, &(&1 + max(total_h - used, 0)))
    else
      # Too short even for the fixed sections: no room for flex (0), and the fixed sections shrink in
      # stack order against a running budget — a lower section collapses to 0 (not rendered) before
      # anything is placed off-frame.
      shrink_to_fit(fixed, total_h)
    end
  end

  defp shrink_to_fit(sections, total_h) do
    {resolved, _left} =
      Enum.map_reduce(sections, total_h, fn nominal, left ->
        take = min(nominal || 0, left)
        {take, left - take}
      end)

    resolved
  end

  # The picker box is intrinsically short: header + blank + one row per space, plus its frame.
  defp fixed_height(Panel.Spaces), do: length(Space.all()) + 4
  # The WindowBar/Pulse bands framing the Tlön terminal: one content row + their own 2-row frame.
  defp fixed_height(Panel.WindowBar), do: 3
  defp fixed_height(Panel.Pulse), do: 3
  defp fixed_height({panel, _read_key}), do: fixed_height(panel)
  defp fixed_height(_panel), do: nil

  # The Tlön window strip, presence-joined: `reads.machine`'s tabs (from `tlon_tabs()`, forked
  # once per render by the Cockpit) each get their agent handle (window → agent via
  # `Aleph.Mention.coworkers/1`, inverted, sourced from the active space's roster) and warmth
  # (`reads.roster`, already fetched for the sidebar) — so WindowBar stays a pure render with no
  # funes reads of its own.
  # C3.1: the strip is LEADERS only — `t<id>` leaf windows (spawned by ensure_thread_sessions) move
  # to the Leaves panel. Reject by the leaf-name shape, not a roster allowlist, so an unexpected
  # leader window (roster not yet loaded, a hand-made window) still shows rather than vanishing.
  @leaf_window ~r/^t\d+$/

  defp window_tabs(r) do
    agents = Map.new(Mention.coworkers(fetch_space(r.active_key).roster), fn {agent, window} -> {window, agent} end)
    warm_agents = r.roster |> Enum.filter(& &1.warm?) |> MapSet.new(& &1.agent)

    r
    |> Map.get(:machine, %{})
    |> tabs_of()
    |> Enum.reject(&Regex.match?(@leaf_window, &1.name))
    |> Enum.map(fn tab ->
      agent = agents[tab.name]
      Map.merge(tab, %{agent: agent, warm?: agent != nil and MapSet.member?(warm_agents, agent)})
    end)
  end

  defp tabs_of(%{tabs: tabs}), do: tabs
  defp tabs_of(_render_state), do: []

  # C3.2: tag the Leaves data with the active leader (the focused WindowBar tab's agent handle) so
  # the panel floats that leader's leaves to the top. nil orbis (funes down) stays nil.
  defp with_focused_lead(nil, _r), do: nil
  defp with_focused_lead(orbis, r), do: Map.put(orbis, :focused_lead, focused_lead(r))

  defp focused_lead(r), do: r |> window_tabs() |> Enum.find_value(fn t -> if t.active?, do: t.agent end)

  # The Claude-engine clock readout: `:off` only once the operator has manually clocked "claude"
  # out (`Funes.Presence.clock_out/1`, e.g. from `funes:console`) — nothing calls that today, so
  # this reads `:on` until that console verb exists. A real per-agent engine reader (§3b,
  # `Funes.Presence.Engine`) is a later, local backend swapped into the same seam.
  defp engine_state, do: if("claude" in Presence.clocked_out_engines(), do: :off, else: :on)

  defp clamp_col(v, w), do: v |> max(@min_col) |> min(max(div(w, 3), @min_col))
end
