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

  # {keycap, label} pairs — keycaps lit in amber, labels dim.
  @hints [{"n", "new"}, {"s", "spawn"}, {"Tab", "space"}, {"↑↓", "thread"}, {"⏎", "focus"}, {"q", "quit"}]

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

    Panel.clip([justify(left, right, rect.w), hints_row()], rect)
  end

  defp hints_row do
    Enum.flat_map(@hints, fn {key, label} ->
      [{key, :header}, {" #{label}", :dim}, {"   ", :dim}]
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
