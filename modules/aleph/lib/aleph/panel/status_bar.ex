defmodule Aleph.Panel.StatusBar do
  @moduledoc """
  The bottom status footer — two rows, always present:

    * an **info** line, justified into sections: a space *tab* and the focused thread on the left,
      the global counts (open threads, live sessions) as chips on the right;
    * a **hints** line: the key bindings, keycaps lit against dim labels.

  The gap between left and right is neutral (never a chip background), so the footer frames the
  screen instead of flooding it. Data is `%{space, thread, thread_count, live_count}`.
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  # {keycap, label} pairs — keycaps lit in amber, labels dim. The tmux-style model: the center
  # owns the keys by default, so aleph's commands are reached through the ^B leader. (In a
  # nav-default space — no live terminal — these are also bare; the hints name the universal path.)
  @hints [
    {"^␣", "aleph"},
    {"^␣n", "new"},
    {"^␣c", "post"},
    {"^␣⏎", "spawn"},
    {"^␣Tab", "space"},
    {"^␣↑↓", "thread"},
    {"^␣q", "quit"}
  ]
  @leader_hints [{"^␣ …", :header}, {"  prefix armed — Esc cancels", :dim}]

  @impl Panel
  def topics(_assigns), do: []

  # Composer mode: the info line becomes the prompt over the CURRENT line of the buffer (the one
  # the cursor is on — not always the last, once Up/Down have moved it), split at the cursor so the
  # marker lands where it actually is, and the hints name the four composer keys. A multiline
  # body's other lines are dropped from this single visible line; the posted message keeps them all.
  @impl Panel
  def render(%{input: %{kind: :compose} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" COMPOSE ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" post", :dim},
      {"   ", :dim},
      {"⇧⏎", :header},
      {" newline", :dim},
      {"  ", :dim},
      {"←→↑↓", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # Title input mode: the info line becomes the prompt, split at the cursor (a caret marks it),
  # and the hints line names only the keys that do anything while typing.
  @impl Panel
  def render(%{input: %{kind: :new_thread} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW THREAD ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" create", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # The author face's create-world prompt (D2.3): the info line becomes the prompt over the typed
  # name, prefixed by the armed template — h/l cycles it, named in the hints.
  @impl Panel
  def render(%{input: %{kind: :new_world, template: template} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW WORLD ", :tab},
      {"  ", :normal},
      {"◂ #{template} ▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" create", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"h/l", :header},
      {" template", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # The field editor's paths sub-list `a` add (D2.4 Chunk 2b): the info line becomes the prompt
  # over the typed path.
  @impl Panel
  def render(%{input: %{kind: :new_path} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW PATH ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" add", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # A transient result line (a spawn's pane id, or its failure reason) — the operator's feedback
  # that `n`/`s` did something. Shown until the next keypress clears it.
  @impl Panel
  def render(%{flash: flash}, rect) when is_binary(flash) do
    info = [{" ", :normal}, {"▸ ", :accent}, {flash, :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row()], rect)
  end

  # The prefix is armed (Ctrl+Space was pressed, awaiting the next key) — show the prefix state
  # instead of the command hints, so the operator knows the next key is aleph's, not the terminal's.
  @impl Panel
  def render(%{leader_pending?: true}, rect) do
    info = [{" ", :normal}, {"▸ ^␣ ", :accent}, {"prefix armed", :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row(@leader_hints)], rect)
  end

  @impl Panel
  def render(%{space: space} = data, rect) do
    focus = data[:focus]
    thread = data[:thread] || "—"
    threads = data[:thread_count] || 0
    live = data[:live_count] || 0

    left =
      mode_chip(focus) ++
        [
          {" #{space} ", :tab},
          {"  ", :normal},
          {"▸ ", :accent},
          {thread, :normal}
        ]

    right = [
      {" ◷ #{threads} threads ", :stat},
      {" ", :normal},
      {" ● #{live} live ", :stat_live}
    ]

    Panel.clip([justify(left, right, rect.w), hints_row(hints_for(space, focus))], rect)
  end

  # Tlön's nav/terminal mode as a leading chip, so you always know whether keys go to tmux (TERM)
  # or drive the panes (NAV). Absent for spaces without a focus model.
  defp mode_chip(%{in_terminal?: true}), do: [{" TERM ", :stat_live}, {" ", :normal}]
  defp mode_chip(%{in_terminal?: false}), do: [{" NAV ", :stat}, {" ", :normal}]
  defp mode_chip(_focus), do: []

  # The CURRENT line of a (possibly multiline) input buffer, split into the text before/after the
  # cursor — what the composer's single visible line renders around the `▎` marker. `cursor`
  # defaults to the buffer's end when absent (a state from before this field existed), matching
  # the old always-at-the-end rendering.
  defp cursor_split(%{buffer: buffer} = input) do
    cursor = Map.get(input, :cursor, String.length(buffer))
    {before, aft} = buffer |> String.graphemes() |> Enum.split(cursor)
    before_line = before |> Enum.join() |> String.split("\n") |> List.last()

    after_line =
      aft
      |> Enum.join()
      |> String.split("\n", parts: 2)
      |> List.first()

    {before_line, after_line}
  end

  defp hints_row, do: hints_row(@hints)

  # Tlön drives its panes with the focus model (not the shared leader), so its hints name those
  # keys and change with the mode. In the terminal only the toggle-out is an aleph key (the rest
  # forwards to tmux); in nav mode aleph owns the keys — pane/column/section movement plus the
  # bare verbs. Focus nil (defensive) or any other space falls back to the shared hint table.
  defp hints_for("Tlön", %{in_terminal?: true}), do: [{"^␣", "nav mode"}]

  defp hints_for("Tlön", %{in_terminal?: false}),
    do: [
      {"h/l", "pane"},
      {"H/L", "col"},
      {"Tab", "section"},
      {"[/]", "space"},
      {"c", "post"},
      {"m", "driver"},
      {"q", "quit"},
      {"Esc", "term"}
    ]

  defp hints_for(space, _focus), do: hints_for(space)

  # Tlön alone carries the settings verb — the only space with a coworker to point it at.
  defp hints_for("Tlön"), do: @hints ++ [{"^␣m", "driver"}]
  defp hints_for(_space), do: @hints

  defp hints_row(hints) do
    Enum.flat_map(hints, fn
      {key, label} when is_binary(label) -> [{key, :header}, {" #{label}", :dim}, {"   ", :dim}]
      {text, style} -> [{text, style}]
    end)
  end

  # Left-align `left`, right-align `right`, fill the middle with neutral spaces to exactly `w`.
  # When too narrow for both, keep the left (clip/1 trims it) — the thread matters more than counts.
  defp justify(left, right, w) do
    gap = w - Panel.row_width(left) - Panel.row_width(right)

    if gap >= 1,
      do: left ++ [{String.duplicate(" ", gap), :normal}] ++ right,
      else: left
  end
end
