defmodule Aleph.Cockpit do
  @moduledoc """
  The live loop and the cockpit's one brain (design §8). It *is* the dispatcher: termbox2 paints
  (output-only), `Raxol.Terminal.Driver` feeds it `:key`/`:resize` events as GenServer casts, and
  `Funes.Bus` events arrive as plain messages. Every input, resize, Bus event, and tick reloads
  the funes reads and repaints. Holds the only shared state — the active workspace and the focused
  thread (§8) — and caches nothing about tmux past the paint (§5).

  Not supervised at app boot: it grabs the TTY, so it runs only under `mix aleph.run` in a real
  terminal, never during `mix test`.
  """
  use GenServer
  require Logger

  alias Aleph.{Board, Tmux, View, Workspace}
  alias Funes.{Bus, Channel, Staff}
  alias Raxol.Core.Events.Event

  # Redraw cadence for tmux liveness + roster warmth, independent of Bus events.
  @tick_ms 500
  @tb_output_truecolor 5

  @doc "Start the cockpit and block until the operator quits — the entry point `mix aleph.run` calls."
  @spec run() :: :ok
  def run do
    # Unlinked + monitored: a cockpit crash surfaces here as a clean DOWN, not a linked exit that
    # takes the task process down before it can restore the terminal.
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

      {:error, {:tb_init_failed, code}} ->
        IO.puts(
          :stderr,
          "aleph needs a real terminal (tb_init returned #{code}) — run this in ghostty."
        )

        :ok

      {:error, reason} ->
        IO.puts(:stderr, "aleph failed to start: #{inspect(reason)}")
        :ok
    end
  end

  @impl true
  def init(_opts) do
    # Subscribe before the first read so nothing posted mid-boot is missed.
    Bus.subscribe_sessions()
    Bus.subscribe_threads()
    Bus.subscribe_messages()

    case :termbox2_nif.tb_init() do
      0 ->
        :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())

        state =
          %{
            driver: driver,
            w: max(:termbox2_nif.tb_width(), 1),
            h: max(:termbox2_nif.tb_height(), 1),
            active_key: List.first(Workspace.all()).key,
            focused_id: nil,
            threads: [],
            subscribed_thread: nil,
            center_focused?: false
          }
          |> render()

        Process.send_after(self(), :tick, @tick_ms)
        {:ok, state}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # --- input + resize from the termbox Driver (GenServer casts) ---

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize, data: %{width: w, height: h}}}, state) do
    {:noreply, render(%{state | w: max(w, 1), h: max(h, 1)})}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    handle_key(key, state)
  end

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # --- Funes.Bus events (plain messages) → reload + repaint ---

  @impl true
  def handle_info({tag, _row}, state)
      when tag in [
             :message_posted,
             :fact_banked,
             :event_recorded,
             :issue_raised,
             :issue_resolved,
             :thread_opened,
             :thread_closed,
             :thread_assigned,
             :session_started,
             :session_ended
           ] do
    {:noreply, render(state)}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, render(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- key handling ---

  # When the center is focused, keys go to the tmux pane; Esc releases.
  defp handle_key(%{key: :escape}, %{center_focused?: true} = state) do
    {:noreply, render(%{state | center_focused?: false})}
  end

  defp handle_key(key, %{center_focused?: true} = state) do
    forward_to_pane(key, state)
    {:noreply, state}
  end

  defp handle_key(%{key: :char, char: "c", ctrl: true}, state), do: quit(state)
  defp handle_key(%{key: :char, char: "q"}, state), do: quit(state)

  defp handle_key(%{key: :tab, shift: true}, state),
    do: {:noreply, switch_workspace(state, :prev)}

  defp handle_key(%{key: :tab}, state), do: {:noreply, switch_workspace(state, :next)}
  defp handle_key(%{key: :char, char: "]"}, state), do: {:noreply, switch_workspace(state, :next)}
  defp handle_key(%{key: :char, char: "["}, state), do: {:noreply, switch_workspace(state, :prev)}

  defp handle_key(%{key: :up}, state), do: {:noreply, move_focus(state, -1)}
  defp handle_key(%{key: :char, char: "k"}, state), do: {:noreply, move_focus(state, -1)}
  defp handle_key(%{key: :down}, state), do: {:noreply, move_focus(state, 1)}
  defp handle_key(%{key: :char, char: "j"}, state), do: {:noreply, move_focus(state, 1)}

  # Enter focuses the center only when it's a terminal surface to type into.
  defp handle_key(%{key: :enter}, %{active_key: :terminal} = state) do
    {:noreply, render(%{state | center_focused?: true})}
  end

  defp handle_key(_key, state), do: {:noreply, state}

  defp switch_workspace(state, dir) do
    ws =
      if dir == :next,
        do: Workspace.next(state.active_key),
        else: Workspace.prev(state.active_key)

    render(%{state | active_key: ws.key, center_focused?: false})
  end

  # Move the focused thread up/down the current list, clamped (no wrap — a list edge should feel like one).
  defp move_focus(%{threads: []} = state, _dir), do: state

  defp move_focus(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    new_id = Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))
    render(%{state | focused_id: new_id})
  end

  # --- forward a keypress to the focused tmux pane ---
  defp forward_to_pane(key, state) do
    pane = pane_ref(focused(state))

    Enum.each(tmux_keys(key), fn
      {:text, t} -> Tmux.send_text(pane, t)
      {:key, k} -> Tmux.send_key(pane, k)
    end)
  end

  defp tmux_keys(%{key: :char, char: c, ctrl: true}), do: [{:key, "C-#{c}"}]
  defp tmux_keys(%{key: :char, char: c}), do: [{:text, c}]
  defp tmux_keys(%{key: :enter}), do: [{:key, "Enter"}]
  defp tmux_keys(%{key: :backspace}), do: [{:key, "BSpace"}]
  defp tmux_keys(%{key: :tab}), do: [{:key, "Tab"}]
  defp tmux_keys(%{key: :up}), do: [{:key, "Up"}]
  defp tmux_keys(%{key: :down}), do: [{:key, "Down"}]
  defp tmux_keys(%{key: :left}), do: [{:key, "Left"}]
  defp tmux_keys(%{key: :right}), do: [{:key, "Right"}]
  defp tmux_keys(_), do: []

  # --- render ---

  defp render(state) do
    threads = Channel.open_threads()
    focused = focused_thread(threads, state.focused_id)
    state = %{state | threads: threads, focused_id: focused && focused.id} |> resubscribe(focused)

    reads = %{
      active_key: state.active_key,
      focused_id: focused && focused.id,
      focused_title: focused && focused.title,
      roster: Staff.roster(),
      threads: threads,
      scope: focused && Funes.Board.in_scope(focused),
      chatter: (focused && Channel.recent_messages(focused, 30)) || [],
      session: session_read(state, focused)
    }

    View.compose(reads, state.w, state.h)
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    state
  end

  defp focused(state), do: focused_thread(state.threads, state.focused_id)

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The center is a live tmux view only in the terminal workspace; elsewhere it isn't shown.
  defp session_read(%{active_key: :terminal} = state, focused) when not is_nil(focused) do
    pane = pane_ref(focused)

    case Tmux.capture(pane, %{h: state.h}) do
      :no_session -> :no_session
      lines -> %{target: pane, lines: lines, focused?: state.center_focused?}
    end
  end

  defp session_read(_state, _focused), do: :no_session

  defp pane_ref(nil), do: nil

  defp pane_ref(thread) do
    case Staff.session_for_thread(thread) do
      %{pane_ref: ref} -> ref
      _ -> nil
    end
  end

  # Follow the focused thread's Bus topic so its dossier/chat repaint on new activity.
  defp resubscribe(state, focused) do
    id = focused && focused.id

    cond do
      id == state.subscribed_thread ->
        state

      true ->
        if state.subscribed_thread, do: Bus.unsubscribe_thread(state.subscribed_thread)
        if id, do: Bus.subscribe_thread(id)
        %{state | subscribed_thread: id}
    end
  end

  defp quit(state) do
    teardown(state)
    {:stop, :normal, state}
  end

  defp teardown(state) do
    if is_pid(state.driver) and Process.alive?(state.driver),
      do: GenServer.stop(state.driver, :normal, 500)

    :termbox2_nif.tb_shutdown()
  rescue
    _ -> :ok
  end
end
