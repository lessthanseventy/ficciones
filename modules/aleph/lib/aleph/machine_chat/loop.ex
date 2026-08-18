defmodule Aleph.MachineChat.Loop do
  @moduledoc """
  The termbox host loop for the Tlön machine-chat tab — a minimal cousin of `Aleph.Cockpit` that
  paints ONE panel (`Aleph.Transcript`) full-screen and drives it from two inputs: a db poll and
  stdin keys/wheel (via `Raxol.Terminal.Driver`). All logical state lives in the pure
  `Aleph.MachineChat.Host`; this module owns only the TTY, the poll timer, and the geometry-aware
  scroll (which `Host`, being pure, can't compute). Not unit-tested — it grabs the TTY (aleph's law:
  test the pure seams, run the loop live).

  It's a READER: a separate OS process from the cockpit, so it can't share the node-local
  `Funes.Bus`; it polls `Funes.Channel.machine_threads/1` off the shared `FUNES_DB` instead.

  Rendering is COALESCED like the cockpit: a scroll event only updates the (cheaply clamped) offset
  and arms a single `:render`, so a fast wheel-burst collapses into one paint per frame instead of
  flooding the mailbox with a full transcript render each. The scroll offset is clamped per-event
  against the `max_scroll` cached by the last paint, so over-scrolling past the bottom is discarded
  rather than piling up (which used to make scrolling back feel stuck).
  """
  use GenServer

  alias Aleph.Board
  alias Aleph.MachineChat.Host
  alias Aleph.Transcript
  alias Funes.Channel
  alias Raxol.Core.Events.Event

  # Poll cadence for new messages — live enough for a conversation, cheap against a quiet WAL.
  @poll_ms 700
  # Coalesce a burst of scroll/poll events into ONE paint on this cadence (~120fps), so fast
  # scrolling stays smooth instead of serializing a full render per event (the cockpit's trick).
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  # TB_INPUT_ESC (1) | TB_INPUT_MOUSE (4) = 5: ESC-sequence parsing AND mouse reporting, so the
  # raxol Driver emits wheel events we scroll on (the cockpit's proven input mode).
  @tb_input_esc_mouse 5
  # Lines a single wheel notch scrolls — the usual terminal step.
  @wheel_lines 3
  # Unclipped render height — render the transcript this tall once, then window it by the offset.
  @max_rows 10_000

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
        :termbox2_nif.tb_set_input_mode(@tb_input_esc_mouse)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())

        state = %{
          driver: driver,
          w: max(:termbox2_nif.tb_width(), 1),
          h: max(:termbox2_nif.tb_height(), 1),
          view: Host.new(),
          scroll: 0,
          max_scroll: 0,
          follow?: true,
          render_armed?: false
        }

        # Load the first frame immediately, then settle into the poll cadence.
        send(self(), :poll)
        {:ok, paint(state)}

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
    {:noreply, schedule_render(%{refresh_size(state) | view: view})}
  end

  # The coalesced paint. A `:render` that arrives already disarmed (a later event painted first) is a
  # no-op, so a burst never double-paints.
  def handle_info(:render, %{render_armed?: false} = state), do: {:noreply, state}
  def handle_info(:render, state), do: {:noreply, paint(%{state | render_armed?: false})}

  # The input Driver died — we can't take keys anymore, so stop; terminate/2 restores the tty.
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state) do
    {:noreply, schedule_render(refresh_size(state))}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    dispatch(action_for(key), state)
  end

  # The wheel scrolls the transcript a few lines — same offset path as the keys.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_up}}}, state),
    do: {:noreply, scroll_by(state, -@wheel_lines)}

  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_down}}}, state),
    do: {:noreply, scroll_by(state, @wheel_lines)}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # The machine chat is really ONE long conversation (the active machine thread dominates), so the
  # arrow/jk keys SCROLL it. Page keys jump a screenful; g/Home and G/End/Enter snap to top and
  # bottom (bottom re-arms tail-follow). `z` zooms the newest thread full-pane, `q` quits.
  defp dispatch(:ignore, state), do: {:noreply, state}
  defp dispatch(:line_up, state), do: {:noreply, scroll_by(state, -1)}
  defp dispatch(:line_down, state), do: {:noreply, scroll_by(state, 1)}
  defp dispatch(:page_up, state), do: {:noreply, scroll_by(state, -page(state))}
  defp dispatch(:page_down, state), do: {:noreply, scroll_by(state, page(state))}
  defp dispatch(:top, state), do: {:noreply, schedule_render(%{state | scroll: 0, follow?: false})}
  defp dispatch(:bottom, state), do: {:noreply, schedule_render(%{state | scroll: state.max_scroll, follow?: true})}

  # Logical actions the pure Host owns (zoom/unzoom/quit). `q` stops the loop; terminate/2 restores
  # the tty on the way out.
  defp dispatch(action, state) do
    view = Host.handle_key(state.view, action)
    if view.quit, do: {:stop, :normal, %{state | view: view}}, else: {:noreply, schedule_render(%{state | view: view})}
  end

  # Move the offset by `delta` lines, clamped to `[0, max_scroll]` using the cached bound so it's
  # cheap (no render) and excess fast-scroll is discarded; reaching the bottom re-arms tail-follow.
  defp scroll_by(state, delta) do
    scroll = (state.scroll + delta) |> min(state.max_scroll) |> max(0)
    schedule_render(%{state | scroll: scroll, follow?: scroll >= state.max_scroll})
  end

  defp action_for(%{key: :char, char: "j"}), do: :line_down
  defp action_for(%{key: :char, char: "k"}), do: :line_up
  defp action_for(%{key: :char, char: "g"}), do: :top
  defp action_for(%{key: :char, char: "G"}), do: :bottom
  defp action_for(%{key: :char, char: "z"}), do: :zoom
  defp action_for(%{key: :char, char: "q"}), do: :quit
  defp action_for(%{key: :char}), do: :ignore
  defp action_for(%{key: :down}), do: :line_down
  defp action_for(%{key: :up}), do: :line_up
  defp action_for(%{key: :page_down}), do: :page_down
  defp action_for(%{key: :page_up}), do: :page_up
  defp action_for(%{key: :home}), do: :top
  defp action_for(%{key: k}) when k in [:end, :enter, :space], do: :bottom
  defp action_for(%{key: :escape}), do: :back
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

  # Arm ONE coalesced paint if none is pending; further events until it fires just update state and
  # see the flag set, so the mailbox drains cheaply and a single :render catches up.
  defp schedule_render(%{render_armed?: true} = state), do: state

  defp schedule_render(state) do
    Process.send_after(self(), :render, @render_coalesce_ms)
    %{state | render_armed?: true}
  end

  # Render the transcript ONCE at full height, cache the resulting scroll bound, then window the
  # rows by the offset (re-pinned to the bottom while following) and blit them. One render per frame.
  defp paint(state) do
    rows = Transcript.render(state.view, %{x: 0, y: 0, w: state.w, h: @max_rows})
    max_scroll = max(length(rows) - state.h, 0)
    scroll = if state.follow?, do: max_scroll, else: min(state.scroll, max_scroll)

    rows
    |> Enum.drop(scroll)
    |> Enum.take(state.h)
    |> Board.rows_to_cells(%{x: 0, y: 0, w: state.w, h: state.h})
    |> Board.paint()

    %{state | scroll: scroll, max_scroll: max_scroll, follow?: state.follow? or scroll >= max_scroll}
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
