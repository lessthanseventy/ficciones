defmodule Aleph.Cockpit do
  @moduledoc """
  The live loop and the cockpit's one brain (design §8). It *is* the dispatcher: termbox2 paints
  (output-only), `Raxol.Terminal.Driver` feeds it `:key`/`:resize` events as GenServer casts, and
  `Funes.Bus` events arrive as plain messages. Every input, resize, Bus event, and tick reloads
  the funes reads and repaints. Holds the only shared state — the active space and the focused
  thread (§8) — and caches nothing about tmux past the paint (§5).

  Not supervised at app boot: it grabs the TTY, so it runs only under `mix aleph.run` in a real
  terminal, never during `mix test`.
  """
  use GenServer

  alias Aleph.Board
  alias Aleph.Keymap
  alias Aleph.Space
  alias Aleph.Spawn
  alias Aleph.Tmux
  alias Aleph.View
  alias Funes.Bus
  alias Funes.Channel
  alias Funes.Staff
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
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())

        # --- input + resize from the termbox Driver (GenServer casts) ---
        state =
          render(%{
            driver: driver,
            w: max(:termbox2_nif.tb_width(), 1),
            h: max(:termbox2_nif.tb_height(), 1),
            active_key: List.first(Space.all()).key,
            focused_id: nil,
            threads: [],
            subscribed_thread: nil,
            center_focused?: false,
            input: nil,
            flash: nil
          })

        Process.send_after(self(), :tick, @tick_ms)
        {:ok, state}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's `tb_init` enables DECCKM (application cursor keys, `ESC[?1h` — see termbox2.h's
  # ENTER_KEYPAD cap), which makes arrow keys arrive as SS3 (`ESC O A`). Raxol's ANSI
  # `InputParser` decodes CSI arrows (`ESC [ A`) but not SS3 ones, so under DECCKM every arrow
  # --- Funes.Bus events (plain messages) → reload + repaint ---

  # mis-parses (to Alt+O + a stray char) and the cockpit never sees `:up`/`:down` — only `j`/`k`
  # worked. Reset DECCKM to normal cursor keys so arrows come through as CSI, which the parser
  # handles. Written to `/dev/tty` because that's the fd termbox drives (not necessarily stdout);
  # termbox's own shutdown sends the same reset, so this only brings it forward to boot.
  defp normalize_cursor_keys do
    # Best-effort: if /dev/tty can't be written we simply keep termbox's default cursor-key mode.
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize, data: %{width: w, height: h}}}, state) do
    {:noreply, render(%{state | w: max(w, 1), h: max(h, 1)})}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    # Any keypress clears a prior flash (a spawn/create result), so it shows until you act again.
    {state, effect} = Keymap.handle(key, %{state | flash: nil})
    apply_effect(effect, state)
  end

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

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
    # Re-read the terminal size every tick, so a resize that never arrived as an event (a missed
    # SIGWINCH, a tmux pane resize) self-corrects within a tick instead of leaving the layout
    # stranded at the old size (black gutters on the right/bottom).
    {:noreply, render(refresh_size(state))}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp refresh_size(state) do
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # --- interpret the reducer's effect (`Aleph.Keymap`) ---

  # State transitions live in the pure `Aleph.Keymap`; the Cockpit only runs the side effect it
  # asks for — repaint, quit, or forward a key to the focused tmux pane.
  defp apply_effect(:repaint, state), do: {:noreply, render(state)}
  # --- render ---
  defp apply_effect(:none, state), do: {:noreply, state}
  defp apply_effect(:quit, state), do: quit(state)

  defp apply_effect({:forward, key}, state) do
    forward_to_pane(key, state)
    {:noreply, state}
  end

  # The `n` verb landed: open the thread, focus it, AND spawn a harness onto it in one motion —
  # a new thread is a new piece of work, so `n` starts working on it rather than making you press
  # `s` next. A bad title just flashes the error.
  defp apply_effect({:create_thread, title}, state) do
    case Channel.open_thread(%{title: title}) do
      {:ok, thread} -> {:noreply, render(%{state | focused_id: thread.id, flash: spawn_onto(thread.id)})}
      {:error, _changeset} -> {:noreply, render(%{state | flash: "couldn't create “#{title}”"})}
    end
  end

  # The `s` verb landed: spawn a harness onto the focused thread (for a thread made elsewhere, or
  # to re-staff one). The RESULT — the new pane id, or the real failure reason — flashes in the
  # footer so a spawn is never a silent no-op.
  defp apply_effect({:spawn, thread_id}, state) do
    {:noreply, render(%{state | flash: spawn_onto(thread_id)})}
  end

  # Spawn a harness onto a thread and return a one-line result for the footer flash. The error is
  # surfaced verbatim (e.g. tmux missing, a dead join) — this is the operator's only feedback. A
  # raise or exit in the spawn path becomes a flash too, NEVER an aleph crash: a spawn is a side
  # errand, and losing the whole cockpit to one is the failure this rescue exists to prevent.
  defp spawn_onto(thread_id) do
    agent = Application.get_env(:aleph, :spawn_agent, "pi")

    case Spawn.session(thread_id, agent) do
      {:ok, pane} -> "spawned #{agent} → #{pane} (Sessions space)"
      {:error, reason} -> "spawn failed: #{inspect(reason)}"
    end
  rescue
    e -> "spawn crashed: #{Exception.message(e)}"
  catch
    :exit, reason -> "spawn crashed: #{inspect(reason)}"
  end

  # --- forward a keypress to the focused tmux pane ---
  defp forward_to_pane(key, state) do
    pane = pane_ref(focused(state))

    Enum.each(tmux_keys(key), fn
      {:text, t} -> Tmux.send_text(pane, t)
      {:key, k} -> Tmux.send_key(pane, k)
    end)
  end

  @doc """
  Translate a cockpit key event to what to send the focused tmux pane: a literal `{:text, s}`
  (send-keys -l) or a named `{:key, name}` (a tmux key name). Public because it is the seam a
  forwarded key crosses to the app — a MISSING clause here silently drops the key (an Esc that
  vanished trapped the operator in a fullscreen menu), so it earns a test of its own.
  """
  def tmux_keys(%{key: :char, char: c, ctrl: true}), do: [{:key, "C-#{c}"}]
  def tmux_keys(%{key: :char, char: c}), do: [{:text, c}]
  def tmux_keys(%{key: :enter}), do: [{:key, "Enter"}]
  # Esc MUST translate — the focused app (pi's config menu, vim) uses it to cancel. Without this
  # clause a forwarded Esc fell through to `[]` and vanished, trapping the operator in the app.
  def tmux_keys(%{key: :escape}), do: [{:key, "Escape"}]
  def tmux_keys(%{key: :backspace}), do: [{:key, "BSpace"}]
  def tmux_keys(%{key: :delete}), do: [{:key, "Delete"}]
  def tmux_keys(%{key: :tab}), do: [{:key, "Tab"}]
  def tmux_keys(%{key: :up}), do: [{:key, "Up"}]
  def tmux_keys(%{key: :down}), do: [{:key, "Down"}]
  def tmux_keys(%{key: :left}), do: [{:key, "Left"}]
  def tmux_keys(%{key: :right}), do: [{:key, "Right"}]
  def tmux_keys(%{key: :home}), do: [{:key, "Home"}]
  def tmux_keys(%{key: :end}), do: [{:key, "End"}]
  def tmux_keys(%{key: :page_up}), do: [{:key, "PageUp"}]
  def tmux_keys(%{key: :page_down}), do: [{:key, "PageDown"}]
  def tmux_keys(_), do: []

  defp render(state) do
    # The chorus (thread blocks, most-recent-activity first) is the ONE ordering the whole cockpit
    # navigates by, so ↑/↓ move the highlight down the feed and every open thread is reachable.
    chorus = Channel.chorus()
    threads = Enum.map(chorus, & &1.thread)
    focused = focused_thread(threads, state.focused_id)
    state = resubscribe(%{state | threads: threads, focused_id: focused && focused.id}, focused)

    reads = %{
      active_key: state.active_key,
      focused_id: focused && focused.id,
      focused_title: focused && focused.title,
      roster: Staff.roster(),
      threads: threads,
      scope: focused && Funes.Board.in_scope(focused),
      chatter: (focused && Channel.recent_messages(focused, 30)) || [],
      chorus: chorus,
      session: session_read(state, focused),
      input: state.input,
      flash: state.flash
    }

    reads
    |> View.compose(state.w, state.h)
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    state
  end

  defp focused(state), do: focused_thread(state.threads, state.focused_id)

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The center is a live tmux view only in the Sessions space; elsewhere it isn't shown.
  defp session_read(%{active_key: :sessions} = state, focused) when not is_nil(focused) do
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

    if id == state.subscribed_thread do
      state
    else
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
