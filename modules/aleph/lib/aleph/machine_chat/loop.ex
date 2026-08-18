defmodule Aleph.MachineChat.Loop do
  @moduledoc """
  The termbox host loop for the Tlön machine-chat tab — a minimal cousin of `Aleph.Cockpit` that
  paints ONE panel (`Aleph.Transcript`) full-screen and drives it from two inputs: a db poll and
  stdin keys (via `Raxol.Terminal.Driver`). All logical state lives in the pure
  `Aleph.MachineChat.Host`; this module owns only the TTY, the poll timer, and the geometry-aware
  scroll (which `Host`, being pure, can't compute). Not unit-tested — it grabs the TTY (aleph's law:
  test the pure seams, run the loop live).

  It's a READER: a separate OS process from the cockpit, so it can't share the node-local
  `Funes.Bus`; it polls `Funes.Channel.machine_threads/1` off the shared `FUNES_DB` instead.
  """
  use GenServer

  alias Aleph.Board
  alias Aleph.MachineChat.Host
  alias Aleph.Panel
  alias Aleph.Transcript
  alias Funes.Channel
  alias Raxol.Core.Events.Event

  # Poll cadence for new messages — live enough for a conversation, cheap against a quiet WAL.
  @poll_ms 700
  @tb_output_truecolor 5
  # TB_INPUT_ESC (1): keep ESC-sequence parsing (arrows/esc) but no mouse — this tab doesn't select.
  @tb_input_esc 1

  # Force-disarm anything a crash could leave on the host tty: mouse reporting off, leave alt screen,
  # show cursor. Idempotent, straight to /dev/tty so it runs even as the io server winds down.
  @restore "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h"

  @doc "Start the tab and block until the operator quits (`q`) — the entry point the Mix task calls."
  @spec run() :: :ok
  def run do
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> restore_host_tty()
        end

      {:error, {:tb_init_failed, code}} ->
        IO.puts(:stderr, "machine-chat needs a real terminal (tb_init returned #{code}) — run it in a tmux pane.")

      {:error, reason} ->
        IO.puts(:stderr, "machine-chat failed to start: #{inspect(reason)}")
    end
  end

  @impl true
  def init(_opts) do
    case :termbox2_nif.tb_init() do
      0 ->
        # Trap exits so a crash anywhere runs terminate/2, restoring the tty (else the pane is left
        # in alt-screen + mouse mode until a manual `reset`).
        Process.flag(:trap_exit, true)
        :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
        :termbox2_nif.tb_set_input_mode(@tb_input_esc)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())

        state = %{
          driver: driver,
          w: max(:termbox2_nif.tb_width(), 1),
          h: max(:termbox2_nif.tb_height(), 1),
          view: Host.new(),
          scroll: 0,
          follow?: true
        }

        # Load the first frame immediately, then settle into the poll cadence.
        send(self(), :poll)
        {:ok, render(state)}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's tb_init enables application cursor keys (DECCKM) → arrows arrive as SS3, which raxol's
  # InputParser doesn't decode; reset on /dev/tty so they come through as CSI and :up/:down fire.
  defp normalize_cursor_keys do
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_ms)
    view = Host.merge(state.view, poll_blocks(state))
    {:noreply, render(%{refresh_size(state) | view: view})}
  end

  # The input Driver died — we can't take keys anymore, so stop; terminate/2 restores the tty.
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state) do
    {:noreply, render(refresh_size(state))}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    dispatch(action_for(key), state)
  end

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # PgUp/PgDn scroll the pane and toggle tail-follow; the rest are logical actions the pure Host owns.
  # `q` stops the loop (terminate/2 restores the tty on the way out).
  defp dispatch(:ignore, state), do: {:noreply, state}

  defp dispatch(:page_up, state),
    do: {:noreply, render(%{state | scroll: max(state.scroll - page(state), 0), follow?: false})}

  defp dispatch(:page_down, state), do: {:noreply, render(%{state | scroll: state.scroll + page(state)})}

  defp dispatch(action, state) do
    view = Host.handle_key(state.view, action)
    if view.quit, do: {:stop, :normal, %{state | view: view}}, else: {:noreply, render(%{state | view: view})}
  end

  defp action_for(%{key: :char, char: "j"}), do: :down
  defp action_for(%{key: :char, char: "k"}), do: :up
  defp action_for(%{key: :char, char: "z"}), do: :zoom
  defp action_for(%{key: :char, char: "q"}), do: :quit
  defp action_for(%{key: :char}), do: :ignore
  defp action_for(%{key: :down}), do: :down
  defp action_for(%{key: :up}), do: :up
  defp action_for(%{key: k}) when k in [:enter, :space], do: :toggle
  defp action_for(%{key: :escape}), do: :back
  defp action_for(%{key: :page_down}), do: :page_down
  defp action_for(%{key: :page_up}), do: :page_up
  defp action_for(_key), do: :ignore

  # A page is one screenful minus a line of overlap, so a reader keeps their place across a jump.
  defp page(state), do: max(state.h - 2, 1)

  # Re-query termbox's size (it only re-learns in the poll path aleph never calls, so tb_resize/0
  # must sync first — see mix.exs and the cockpit's refresh_size).
  defp refresh_size(state) do
    :termbox2_nif.tb_resize()
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # Read the machine-thread blocks; a transient read failure keeps the last good frame rather than
  # crashing the tab — a stale but readable transcript is the right failure mode for a glance tab.
  defp poll_blocks(state) do
    Channel.machine_threads()
  rescue
    _ -> state.view.blocks
  catch
    :exit, _ -> state.view.blocks
  end

  # Paint one full-screen Transcript panel, windowed by the scroll offset: clamp scroll to the
  # content, re-pin to the bottom while following, and re-arm follow when a page-down reaches the end.
  defp render(state) do
    content_h = Panel.content_height(Transcript, state.view, state.w)
    max_scroll = max(content_h - state.h, 0)
    scroll = if state.follow?, do: max_scroll, else: min(state.scroll, max_scroll)
    state = %{state | scroll: scroll, follow?: state.follow? or scroll >= max_scroll}

    rect = %{x: 0, y: 0, w: state.w, h: state.h}

    [{Transcript, Map.put(state.view, :scroll, scroll), rect}]
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    state
  end

  @impl true
  def terminate(_reason, state), do: teardown(state)

  defp teardown(state) do
    try do
      if is_pid(state.driver) and Process.alive?(state.driver), do: GenServer.stop(state.driver, :normal, 500)
    catch
      _, _ -> :ok
    end

    try do
      :termbox2_nif.tb_shutdown()
    catch
      _, _ -> :ok
    end

    restore_host_tty()
  end

  defp restore_host_tty do
    _ = File.write("/dev/tty", @restore)
    :ok
  end
end
