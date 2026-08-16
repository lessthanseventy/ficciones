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
  @hints [{"^B", "aleph"}, {"^Bn", "new"}, {"^B⏎", "spawn"}, {"^BTab", "space"}, {"^B↑↓", "thread"}, {"^Bq", "quit"}]
  @leader_hints [{"^B …", :header}, {"  prefix armed — Esc cancels", :dim}]

  @impl Panel
  def topics(_assigns), do: []

  # Title input mode: the info line becomes the prompt (a caret marks the cursor), and the
  # hints line names only the two keys that do anything while typing.
  @impl Panel
  def render(%{input: %{kind: :new_thread, buffer: buffer}}, rect) do
    prompt = [
      {" NEW THREAD ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {buffer, :normal},
      {"▎", :accent}
    ]

    hints = [{"⏎", :header}, {" create", :dim}, {"   ", :dim}, {"Esc", :header}, {" cancel", :dim}]
    Panel.clip([prompt, hints], rect)
  end

  # A transient result line (a spawn's pane id, or its failure reason) — the operator's feedback
  # that `n`/`s` did something. Shown until the next keypress clears it.
  @impl Panel
  def render(%{flash: flash}, rect) when is_binary(flash) do
    info = [{" ", :normal}, {"▸ ", :accent}, {flash, :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row()], rect)
  end

  # The prefix is armed (Ctrl+B was pressed, awaiting the next key) — show the prefix state
  # instead of the command hints, so the operator knows the next key is aleph's, not the terminal's.
  @impl Panel
  def render(%{leader_pending?: true}, rect) do
    info = [{" ", :normal}, {"▸ ^B ", :accent}, {"prefix armed", :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row(@leader_hints)], rect)
  end

  @impl Panel
  def render(%{space: space} = data, rect) do
    focus = data[:thread] || "—"
    threads = data[:thread_count] || 0
    live = data[:live_count] || 0

    left = [
      {" #{space} ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {focus, :normal}
    ]

    right = [
      {" ◷ #{threads} threads ", :stat},
      {" ", :normal},
      {" ● #{live} live ", :stat_live}
    ]

    Panel.clip([justify(left, right, rect.w), hints_row(@hints)], rect)
  end

  defp hints_row, do: hints_row(@hints)

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
