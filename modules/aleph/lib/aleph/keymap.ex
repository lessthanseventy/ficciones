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
    * `{:create_thread, title}` — open a new thread with this title (the `n` verb, on Enter).
    * `{:spawn, thread_id}` — spawn a harness session onto this thread (the `s` verb).
    * `:none` — nothing to do.

  `state.input` is `nil` in normal mode, or `%{kind: :new_thread, buffer: String.t()}` while the
  operator is typing a title — a modal that captures EVERY key (so `q` types a "q", it does not
  quit) until Enter submits or Esc cancels.
  """

  alias Aleph.Space

  @type effect ::
          :repaint | :quit | {:forward, map()} | {:create_thread, String.t()} | {:spawn, term()} | :none

  @doc "Map a key event against the current state to the next state and the effect to run."
  @spec handle(map(), map()) :: {map(), effect()}

  # --- title input mode: a MODAL — every key belongs to the buffer until Enter/Esc, so a
  # binding letter (q, s, tab) types its character instead of firing. Must come first. ---
  def handle(%{key: :escape}, %{input: %{}} = state), do: {%{state | input: nil}, :repaint}

  # Enter submits — but an empty title creates nothing (cancel), never a blank thread.
  def handle(%{key: :enter}, %{input: %{buffer: ""}} = state), do: {%{state | input: nil}, :repaint}

  def handle(%{key: :enter}, %{input: %{kind: :new_thread, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:create_thread, buffer}}

  def handle(%{key: :backspace}, %{input: %{buffer: buffer} = input} = state),
    do: {%{state | input: %{input | buffer: String.slice(buffer, 0..-2//1)}}, :repaint}

  def handle(%{key: :char, char: c}, %{input: %{buffer: buffer} = input} = state) when is_binary(c),
    do: {%{state | input: %{input | buffer: buffer <> c}}, :repaint}

  # Any other key while typing (arrows, function keys) is ignored, not acted on.
  def handle(_key, %{input: %{}} = state), do: {state, :none}

  # --- center focused: keys belong to the tmux pane; the LEADER (Ctrl+B) is the one that's ours ---
  # Ctrl+B always returns to aleph — even from inside a fullscreen app that traps Esc (a config
  # menu, vim, a REPL). EVERY other key, INCLUDING Esc, forwards to the pane, so the app gets its
  # own keys and can never trap you. (tmux's prefix idea: one reserved key, nothing else stolen.)
  def handle(%{key: :char, char: "b", ctrl: true}, %{center_focused?: true} = state),
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
  def handle(%{key: :enter}, %{active_key: :sessions} = state), do: {%{state | center_focused?: true}, :repaint}

  # --- n: open a new thread (enter title input mode); s: spawn a harness onto the focused thread ---
  def handle(%{key: :char, char: "n"}, state), do: {%{state | input: %{kind: :new_thread, buffer: ""}}, :repaint}

  def handle(%{key: :char, char: "s"}, %{focused_id: nil} = state), do: {state, :none}
  def handle(%{key: :char, char: "s"}, %{focused_id: id} = state), do: {state, {:spawn, id}}

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
