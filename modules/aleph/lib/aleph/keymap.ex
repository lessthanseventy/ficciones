defmodule Aleph.Keymap do
  @moduledoc """
  The cockpit's keyhandling as a **pure reducer** (design §8): `(key_event, state) → {new_state,
  effect}`, with no TTY, no tmux, and no paint. Extracting the decision from the side effect is
  what makes every binding testable headlessly (`Aleph.KeymapTest`) — the `Aleph.Cockpit`
  GenServer stays a thin interpreter of the returned effect.

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): the center
  surface owns the keys by default. A **live terminal** in the center forwards every key to its PTY
  (the terminal is "normal mode"); aleph's own commands are reached through a `Ctrl+B` **leader**
  that arms the *next* key as an aleph command. When there's no live terminal (Comms' chorus, or a
  placeholder before a session spawns), aleph's nav bindings are **bare** — the same command table,
  reached without the prefix. One command table, two doors.

  `state` is the slice of cockpit state keys touch: `active_key`, `focused_id`, `threads`,
  `center_live?` (derived per keypress by the cockpit — true when a live terminal is in the center),
  `leader_pending?` (the prefix is armed), and `input` (the title-typing modal). A `key_event` is
  the `Raxol.Core.Events.Event` `data` map, e.g. `%{key: :up}` or `%{key: :char, char: "j"}`.

  Effects:

    * `:repaint` — state changed; reload funes reads and paint.
    * `:quit` — tear down and stop.
    * `{:forward, key}` — send this key to the focused session's embedded terminal.
    * `{:create_thread, title}` — open a new thread AND spawn a session onto it (the `n` verb).
    * `{:enter_or_spawn, thread_id}` — spawn a session onto an existing focused thread if it has
      none, else no-op (the `Enter` verb — the `s` verb's replacement).
    * `{:focus_pane, pane}` — focus a Tlön machine pane (`:pi` | `:claude`), summoning it if it
      isn't running yet (the `o` verb, tmux's other-pane; Tlön only).
    * `:none` — nothing to do.

  `state.input` is `nil` normally, or `%{kind: :new_thread, buffer: String.t()}` while the operator
  is typing a title — a modal that captures EVERY key (so `q` types a "q", it does not quit) until
  Enter submits or Esc cancels.
  """

  alias Aleph.Space

  @type effect ::
          :repaint
          | :quit
          | {:forward, map()}
          | {:create_thread, String.t()}
          | {:enter_or_spawn, term()}
          | {:focus_pane, :pi | :claude}
          | :none

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

  # --- leader pending: Ctrl+B was pressed; the next key is an aleph command. ---
  # Ctrl+B again → send a LITERAL Ctrl+B through to the terminal (tmux's prefix-twice convention),
  # so an app inside the pane that wants Ctrl+B (nested tmux, vim) still gets it. Only when there's
  # a live terminal to receive it; with no terminal, a literal Ctrl+B has nowhere to go → drop.
  def handle(%{key: :char, char: "b", ctrl: true}, %{leader_pending?: true, center_live?: true} = state),
    do: {%{state | leader_pending?: false}, {:forward, %{key: :char, char: "b", ctrl: true}}}

  def handle(%{key: :char, char: "b", ctrl: true}, %{leader_pending?: true} = state),
    do: {%{state | leader_pending?: false}, :none}

  # Esc cancels a pending prefix without acting — the escape hatch from a half-armed leader.
  def handle(%{key: :escape}, %{leader_pending?: true} = state), do: {%{state | leader_pending?: false}, :repaint}

  # Any other key while the prefix is armed → run the command, then clear the prefix. The command
  # table (`command/2`) is the single source of aleph's bindings, shared with the bare-key path.
  def handle(key, %{leader_pending?: true} = state) do
    {next, effect} = command(key, state)
    {%{next | leader_pending?: false}, effect}
  end

  # --- the leader: Ctrl+B arms the next key as an aleph command. ---
  def handle(%{key: :char, char: "b", ctrl: true}, state), do: {%{state | leader_pending?: true}, :repaint}

  # --- default: the center surface owns the keys. ---
  # A live terminal in the center → every key forwards to its PTY. The terminal is "normal mode";
  # you type into it immediately. (Ctrl+C lands here too → forwards as an interrupt, never a quit.)
  def handle(key, %{center_live?: true} = state), do: {state, {:forward, key}}

  # No live terminal (Comms, or a placeholder before a session spawns) → aleph's nav bindings are
  # bare — the same command table the leader reaches, just without the prefix.
  def handle(key, state), do: command(key, state)

  # --- aleph's command table — one source of bindings, reached two ways: bare in a nav-default
  # space, or via the Ctrl+B leader from inside a running terminal. ---
  defp command(%{key: :char, char: "q"}, state), do: {state, :quit}

  defp command(%{key: :char, char: "n"}, state), do: {%{state | input: %{kind: :new_thread, buffer: ""}}, :repaint}

  # Enter on a focused thread → enter-or-spawn: spawn a session if it has none, else no-op. The
  # replacement for the old `s` verb — creating a thread and spawning are one action (`n` already
  # does both), and "put a session on an existing thread" is this. Sessions space only: anywhere
  # else the center can't show the spawned terminal (Comms renders the chorus, Tlön the machine
  # shell), so Enter would start a live PTY the operator can neither see nor type into.
  defp command(%{key: :enter}, %{active_key: :sessions, focused_id: id} = state) when not is_nil(id),
    do: {state, {:enter_or_spawn, id}}

  defp command(%{key: :enter}, state), do: {state, :none}

  # `o` — the other Tlön machine pane (tmux's other-pane verb): pi ⇄ claude. The cockpit owns
  # the summon side effect (claude spawns lazily on first focus). Unbound outside Tlön.
  defp command(%{key: :char, char: "o"}, %{active_key: :tlon} = state), do: {state, {:focus_pane, other_pane(state)}}

  defp command(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp command(%{key: :tab}, state), do: switch(state, :next)
  defp command(%{key: :char, char: "]"}, state), do: switch(state, :next)
  defp command(%{key: :char, char: "["}, state), do: switch(state, :prev)

  defp command(%{key: :up}, state), do: move(state, -1)
  defp command(%{key: :char, char: "k"}, state), do: move(state, -1)
  defp command(%{key: :down}, state), do: move(state, 1)
  defp command(%{key: :char, char: "j"}, state), do: move(state, 1)

  # Anything else (Ctrl+C, F-keys, page-up…) is unbound — a no-op, never a quit.
  defp command(_key, state), do: {state, :none}

  defp other_pane(%{machine_pane: :claude}), do: :pi
  defp other_pane(_state), do: :claude

  defp switch(state, dir) do
    space =
      if dir == :next,
        do: Space.next(state.active_key),
        else: Space.prev(state.active_key)

    {%{state | active_key: space.key}, :repaint}
  end

  defp move(%{threads: []} = state, _dir), do: {state, :none}

  defp move(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    new_id = Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))
    {%{state | focused_id: new_id}, :repaint}
  end
end
