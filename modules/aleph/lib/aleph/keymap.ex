defmodule Aleph.Keymap do
  @moduledoc """
  The cockpit's keyhandling as a **pure reducer** (design §8): `(key_event, state) → {new_state,
  effect}`, with no TTY, no tmux, and no paint. Extracting the decision from the side effect is
  what makes every binding testable headlessly (`Aleph.KeymapTest`) — the `Aleph.Cockpit`
  GenServer stays a thin interpreter of the returned effect.

  `state` is the slice of cockpit state keys touch: `active_key`, `focused_id`, `threads`,
  `center_focused?`. A `key_event` is the `Raxol.Core.Events.Event` `data` map, e.g.
  `%{key: :up}` or `%{key: :char, char: "j", ctrl: false}`.

  Effects:

    * `:repaint` — state changed; reload funes reads and paint.
    * `:quit` — tear down and stop.
    * `{:forward, key}` — send this key to the focused tmux pane; local state unchanged.
    * `:none` — nothing to do.
  """

  alias Aleph.Space

  @type effect :: :repaint | :quit | {:forward, map()} | :none

  @doc "Map a key event against the current state to the next state and the effect to run."
  @spec handle(map(), map()) :: {map(), effect()}

  # --- center focused: keys belong to the tmux pane; only Esc is ours (release) ---
  def handle(%{key: :escape}, %{center_focused?: true} = state),
    do: {%{state | center_focused?: false}, :repaint}

  def handle(key, %{center_focused?: true} = state), do: {state, {:forward, key}}

  # --- quit ---
  def handle(%{key: :char, char: "c", ctrl: true}, state), do: {state, :quit}
  def handle(%{key: :char, char: "q"}, state), do: {state, :quit}

  # --- space switching (releases center focus) ---
  def handle(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  def handle(%{key: :tab}, state), do: switch(state, :next)
  def handle(%{key: :char, char: "]"}, state), do: switch(state, :next)
  def handle(%{key: :char, char: "["}, state), do: switch(state, :prev)

  # --- thread focus movement (clamped, no wrap) ---
  def handle(%{key: :up}, state), do: move(state, -1)
  def handle(%{key: :char, char: "k"}, state), do: move(state, -1)
  def handle(%{key: :down}, state), do: move(state, 1)
  def handle(%{key: :char, char: "j"}, state), do: move(state, 1)

  # --- Enter focuses the center only when it's a live session to type into (Sessions space) ---
  def handle(%{key: :enter}, %{active_key: :sessions} = state),
    do: {%{state | center_focused?: true}, :repaint}

  # --- anything else is unbound ---
  def handle(_key, state), do: {state, :none}

  defp switch(state, dir) do
    space =
      if dir == :next,
        do: Space.next(state.active_key),
        else: Space.prev(state.active_key)

    {%{state | active_key: space.key, center_focused?: false}, :repaint}
  end

  defp move(%{threads: []} = state, _dir), do: {state, :none}

  defp move(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    new_id = Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))
    {%{state | focused_id: new_id}, :repaint}
  end
end
