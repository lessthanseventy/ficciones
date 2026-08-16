defmodule Aleph.Panel.StatusBar do
  @moduledoc """
  The bottom status footer — two rows, always present:

    * an **info** line, justified into sections: a workspace *tab* and the focused thread on the
      left, the global counts (open threads, live sessions) as chips on the right;
    * a **hints** line: the key bindings, keycaps lit against dim labels.

  The gap between left and right is neutral (never a chip background), so the footer frames the
  screen instead of flooding it. Data is `%{workspace, thread, thread_count, live_count}`.
  """
  @behaviour Aleph.Panel

  alias Aleph.Panel

  # {keycap, label} pairs — keycaps lit in amber, labels dim.
  @hints [{"Tab", "workspace"}, {"↑↓", "thread"}, {"⏎", "focus"}, {"q", "quit"}]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{workspace: workspace} = data, rect) do
    focus = data[:thread] || "—"
    threads = data[:thread_count] || 0
    live = data[:live_count] || 0

    left = [
      {" #{workspace} ", :tab},
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
