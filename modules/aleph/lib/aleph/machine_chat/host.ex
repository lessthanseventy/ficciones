defmodule Aleph.MachineChat.Host do
  @moduledoc """
  The Tlön machine-chat interaction state and its pure reducers — the brain the `aleph.machine_chat`
  termbox loop wraps. Kept free of IO so it's headlessly testable (aleph's law: unit-test the pure
  seams, never the TTY loop).

  State:
    - `blocks`    — the `Funes.Channel.machine_threads/1` read model (most-recent-activity first).
    - `selected`  — index of the highlighted block.
    - `folded`    — the effective folded set (thread ids), computed each merge from `overrides` + the
      default (newest thread expanded, older ones folded).
    - `overrides` — the user's explicit fold choices (`thread_id => folded?`), which survive a poll:
      a manual expand/collapse always wins over the default, even as threads rotate.
    - `zoom`      — the thread id shown full-pane, or `nil`.
    - `follow?`   — whether new messages pin the viewport to the bottom (owned here, applied by the loop).
    - `scroll`    — the vertical offset (applied by the loop).
    - `quit`      — set by `:quit`; the loop tears down on it.
  """

  @type state :: %{
          blocks: [map()],
          selected: non_neg_integer(),
          folded: MapSet.t(),
          overrides: %{optional(term()) => boolean()},
          zoom: term() | nil,
          follow?: boolean(),
          scroll: non_neg_integer(),
          quit: boolean()
        }

  @doc "A fresh interaction state before the first poll."
  @spec new() :: state()
  def new do
    %{
      blocks: [],
      selected: 0,
      folded: MapSet.new(),
      overrides: %{},
      zoom: nil,
      follow?: true,
      scroll: 0,
      quit: false
    }
  end

  @doc """
  Fold a fresh poll into the state: recompute the effective folded set (defaults + surviving manual
  overrides), clamp the selection to the new block count, and drop a zoom whose thread has rotated
  away.
  """
  @spec merge(state(), [map()]) :: state()
  def merge(state, blocks) do
    %{
      state
      | blocks: blocks,
        folded: folded_set(blocks, state.overrides),
        selected: clamp(state.selected, length(blocks)),
        zoom: if(zoom_present?(state.zoom, blocks), do: state.zoom)
    }
  end

  @doc "Advance the interaction state for one key. Unknown keys pass through unchanged."
  @spec handle_key(state(), atom()) :: state()
  def handle_key(state, :down), do: %{state | selected: clamp(state.selected + 1, length(state.blocks))}
  def handle_key(state, :up), do: %{state | selected: max(state.selected - 1, 0)}

  # Folding is a no-op while zoomed (there's a single thread on screen, expanded).
  def handle_key(%{zoom: nil} = state, :toggle) do
    case selected_thread_id(state) do
      nil ->
        state

      tid ->
        overrides = Map.put(state.overrides, tid, not MapSet.member?(state.folded, tid))
        %{state | overrides: overrides, folded: folded_set(state.blocks, overrides)}
    end
  end

  def handle_key(state, :toggle), do: state

  def handle_key(state, :zoom) do
    case selected_thread_id(state) do
      nil -> state
      tid -> %{state | zoom: tid}
    end
  end

  def handle_key(state, :back), do: %{state | zoom: nil}
  def handle_key(state, :quit), do: %{state | quit: true}
  def handle_key(state, _other), do: state

  # The effective folded set: for each thread, the user's override if any, else the default —
  # only the newest (index 0, most-recent activity) thread is expanded.
  defp folded_set(blocks, overrides) do
    blocks
    |> Enum.with_index()
    |> Enum.filter(fn {block, index} -> Map.get(overrides, thread_id(block), index != 0) end)
    |> MapSet.new(fn {block, _index} -> thread_id(block) end)
  end

  defp selected_thread_id(state), do: state.blocks |> Enum.at(state.selected) |> thread_id()

  defp thread_id(nil), do: nil
  defp thread_id(%{thread: %{id: id}}), do: id

  defp zoom_present?(nil, _blocks), do: false
  defp zoom_present?(id, blocks), do: Enum.any?(blocks, &(thread_id(&1) == id))

  defp clamp(_index, 0), do: 0
  defp clamp(index, count), do: index |> min(count - 1) |> max(0)
end
