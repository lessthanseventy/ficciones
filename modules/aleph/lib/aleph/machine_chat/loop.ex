defmodule Aleph.MachineChat.Loop do
  @moduledoc """
  The termbox host loop for the Tlön machine-chat tab — a minimal cousin of `Aleph.Cockpit` that
  paints the `Aleph.Transcript` feed plus a bottom COMPOSER, driven by a db poll and stdin
  keys/wheel (via `Raxol.Terminal.Driver`). Pure logical state lives in `Aleph.MachineChat.Host`;
  this module owns the TTY, the poll timer, the scroll, and the composer. Not unit-tested — it grabs
  the TTY (aleph's law: test the pure seams, run the loop live).

  It's a READER for the feed (polls `Funes.Channel.machine_threads/1` off the shared `FUNES_DB`,
  since the node-local `Funes.Bus` isn't reachable cross-process) but a WRITER for the composer: it
  posts as the operator straight through `Channel`, and wakes any @-mentioned coworker itself by
  `tmux send-keys` (reusing the pure `Aleph.Mention` routing) — the cockpit only wakes agents for
  messages on ITS own bus, which it never sees from here.

  Two MODES:
    * COMPOSE (default) — the bottom box has focus. Type; `Enter` starts a NEW thread/task (opens a
      machine-scope funes thread titled by what you typed, posts it as you, wakes any @-mention);
      `Backspace` edits; `Esc` clears the box, or drops to BROWSE when it's already empty.
    * BROWSE — `j/k` (or `↑↓`) select an episode, `Enter` folds/unfolds it, `z` zooms it to a read,
      `Esc` unzooms or returns to COMPOSE, `i` jumps straight back to COMPOSE.

  Either mode scrolls the feed (wheel, PgUp/PgDn, and — outside typing — arrows/g/G). Slack-style:
  episodes read newest-at-the-bottom, the feed lands at the bottom and tail-follows, bottom-anchored
  above the composer. Rendering is coalesced (one paint per ~8ms frame).
  """
  use GenServer

  alias Aleph.Board
  alias Aleph.Config
  alias Aleph.MachineChat.Host
  alias Aleph.MachineChat.Staffing
  alias Aleph.Mention
  alias Aleph.Transcript
  alias Funes.Channel
  alias Raxol.Core.Events.Event

  # The claude coworker handle — the lead the cockpit staffs with its own `t<id>` session,
  # so this tab must not also wake the standing coworker for it. Keep in sync with
  # `Aleph.Cockpit.@claude_agent`.
  @claude_agent "claude-machine"

  @poll_ms 700
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  @tb_input_esc_mouse 5
  @wheel_lines 3
  @max_rows 10_000
  # Rows reserved at the bottom for the composer: a rule + the input line.
  @box_rows 2

  @restore "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h"

  @doc "Start the tab and block until the operator quits — the entry point the Mix task calls."
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
          render_armed?: false,
          mode: :compose,
          input: "",
          rollup: nil
        }

        send(self(), :poll)
        {:ok, paint(state)}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's tb_init enables DECCKM; reset on /dev/tty so arrows arrive as CSI, not SS3.
  defp normalize_cursor_keys do
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_ms)
    view = Host.merge(state.view, poll_blocks(state))
    view = if state.follow?, do: %{view | selected: max(length(view.blocks) - 1, 0)}, else: view
    {:noreply, schedule_render(%{refresh_size(state) | view: view, rollup: Aleph.Orbis.rollup()})}
  end

  def handle_info(:render, %{render_armed?: false} = state), do: {:noreply, state}
  def handle_info(:render, state), do: {:noreply, paint(%{state | render_armed?: false})}
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state), do: {:noreply, schedule_render(refresh_size(state))}

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{mode: :compose} = state), do: compose_key(key, state)
  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state), do: browse_key(intent(key), state)

  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_up}}}, state),
    do: {:noreply, scroll_by(state, -@wheel_lines)}

  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_down}}}, state),
    do: {:noreply, scroll_by(state, @wheel_lines)}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # COMPOSE: printable keys build the task text; Enter kicks it off; Esc clears or drops to browse.
  defp compose_key(%{key: :char, char: c}, state), do: {:noreply, schedule_render(%{state | input: state.input <> c})}
  defp compose_key(%{key: :space}, state), do: {:noreply, schedule_render(%{state | input: state.input <> " "})}
  defp compose_key(%{key: :backspace}, state), do: {:noreply, schedule_render(backspace(state))}
  defp compose_key(%{key: :enter}, state), do: {:noreply, schedule_render(submit(state))}
  defp compose_key(%{key: :escape}, %{input: ""} = state), do: {:noreply, schedule_render(%{state | mode: :browse})}
  defp compose_key(%{key: :escape}, state), do: {:noreply, schedule_render(%{state | input: ""})}

  defp compose_key(%{key: k}, state) when k in [:up, :down, :page_up, :page_down, :home, :end],
    do: {:noreply, scroll_key(k, state)}

  defp compose_key(_key, state), do: {:noreply, state}

  # BROWSE splits on whether an episode is zoomed: zoomed → scroll it; list → select/fold/zoom.
  defp browse_key(intent, %{view: %{zoom: z}} = state) when not is_nil(z), do: browse_zoom(intent, state)
  defp browse_key(intent, state), do: browse_list(intent, state)

  defp browse_list(:next, state), do: {:noreply, host_view(state, :down)}
  defp browse_list(:prev, state), do: {:noreply, host_view(state, :up)}
  defp browse_list(:enter, state), do: {:noreply, host_view(state, :toggle)}
  defp browse_list(:zoom, state), do: {:noreply, host_view(%{state | follow?: true}, :zoom)}
  defp browse_list(:back, state), do: {:noreply, schedule_render(%{state | mode: :compose})}
  defp browse_list(:compose, state), do: {:noreply, schedule_render(%{state | mode: :compose})}
  defp browse_list(:pgdn, state), do: {:noreply, scroll_by(state, page(state))}
  defp browse_list(:pgup, state), do: {:noreply, scroll_by(state, -page(state))}
  defp browse_list(:top, state), do: {:noreply, schedule_render(%{state | scroll: 0, follow?: false})}
  defp browse_list(:bottom, state), do: {:noreply, schedule_render(%{state | follow?: true})}
  defp browse_list(_other, state), do: {:noreply, state}

  defp browse_zoom(:back, state), do: {:noreply, host_view(%{state | follow?: true}, :back)}
  defp browse_zoom(:next, state), do: {:noreply, scroll_by(state, 1)}
  defp browse_zoom(:prev, state), do: {:noreply, scroll_by(state, -1)}
  defp browse_zoom(:pgdn, state), do: {:noreply, scroll_by(state, page(state))}
  defp browse_zoom(:pgup, state), do: {:noreply, scroll_by(state, -page(state))}
  defp browse_zoom(:top, state), do: {:noreply, schedule_render(%{state | scroll: 0, follow?: false})}
  defp browse_zoom(:bottom, state), do: {:noreply, schedule_render(%{state | follow?: true})}
  defp browse_zoom(_other, state), do: {:noreply, state}

  defp host_view(state, action), do: schedule_render(%{state | view: Host.handle_key(state.view, action)})

  # Raw key → a browse-mode intent.
  defp intent(%{key: :char, char: "j"}), do: :next
  defp intent(%{key: :char, char: "k"}), do: :prev
  defp intent(%{key: :char, char: "g"}), do: :top
  defp intent(%{key: :char, char: "G"}), do: :bottom
  defp intent(%{key: :char, char: "z"}), do: :zoom
  defp intent(%{key: :char, char: "i"}), do: :compose
  defp intent(%{key: :char}), do: :ignore
  defp intent(%{key: :down}), do: :next
  defp intent(%{key: :up}), do: :prev
  defp intent(%{key: k}) when k in [:enter, :space], do: :enter
  defp intent(%{key: :escape}), do: :back
  defp intent(%{key: :page_down}), do: :pgdn
  defp intent(%{key: :page_up}), do: :pgup
  defp intent(%{key: :home}), do: :top
  defp intent(%{key: :end}), do: :bottom
  defp intent(_key), do: :ignore

  # Kick off a new thread/task from the composer text: open a machine-scope funes thread titled by
  # it, post it as the operator, wake any @-mentioned coworker, then clear and land at the bottom so
  # the fresh episode is in view. Failures just clear the box rather than crash the tab.
  defp submit(%{input: input} = state) do
    text = String.trim(input)
    if text == "", do: state, else: do_submit(state, text)
  rescue
    _ -> %{state | input: ""}
  catch
    :exit, _ -> %{state | input: ""}
  end

  defp do_submit(state, text) do
    author = Application.get_env(:funes, :operator, "andrew")

    case Channel.open_thread(%{title: text, scope: "machine"}) do
      {:ok, thread} ->
        Channel.post(%{thread_id: thread.id, author: author, body: text})
        lead = stage_lead(thread.id, text)

        # The cockpit (a SEPARATE beam) spawns a dedicated `t<id>` session for a claude-launched
        # lead and injects the opening turn ITSELF (`ensure_thread_sessions`). Waking the
        # standing coworker from here as well is the "both claudes answered" duplicate — so only
        # wake from here for a lead the cockpit won't staff (a pi-led thread).
        if !cockpit_staffs?(lead), do: wake_mentions(author, text, thread.id)

        %{state | input: "", follow?: true}

      _ ->
        %{state | input: ""}
    end
  end

  # Staff the picked coworker (the composer text's first @-mention, else the operator's
  # configured default) as the new thread's lead, returning the staged handle. A staffing failure
  # (an unregistered handle, a DB hiccup) raises up to `submit/1`'s rescue/catch, which just clears
  # the box — the thread and its opening message are already durable either way.
  defp stage_lead(thread_id, text) do
    handle = Staffing.pick_coworker(text, Config.default_coworker())
    Funes.assign_lead(thread_id, handle)
    handle
  end

  # Does the cockpit spawn a per-thread `t<id>` session for this lead (so it owns the opening turn
  # and we must NOT also wake here)? Mirrors `Aleph.Cockpit.claude_launched?/1`: the claude coworker
  # and the optional third experiment agent are claude-launched; a pi-led thread is not.
  defp cockpit_staffs?(lead), do: lead == @claude_agent or lead == third_agent_author()

  defp third_agent_author do
    case Mention.third_agent() do
      %{author: author} -> author
      nil -> nil
    end
  end

  # Wake each @-mentioned coworker by injecting the message as a turn into its tmux window — the same
  # send-keys the cockpit does, but from here (our post is on our own bus, which the cockpit can't
  # see). $TMUX points at the tlon server, so a bare `tmux` targets the right session.
  defp wake_mentions(author, body, thread_id) do
    lead = safe_thread_lead(thread_id)

    for {window, text} <- Mention.route(%{author: author, body: body, thread_id: thread_id}, lead: lead) do
      System.cmd("tmux", ["send-keys", "-t", "tlon:#{window}", "-l", text], stderr_to_stdout: true)
      System.cmd("tmux", ["send-keys", "-t", "tlon:#{window}", "Enter"], stderr_to_stdout: true)
    end

    :ok
  rescue
    _ -> :ok
  end

  # A brand-new thread's lead has no live window yet (the cockpit's spawn+inject is what wakes it) —
  # but for a thread whose lead already has one (the standing coworkers), a bare operator reply must
  # still reach them. Guarded so a Funes hiccup degrades to "wake nobody", never a crash.
  defp safe_thread_lead(tid) do
    Funes.thread_lead(tid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp backspace(%{input: input} = state), do: %{state | input: String.slice(input, 0, max(String.length(input) - 1, 0))}

  # Arrow/page/home/end while composing scroll the feed (they aren't text).
  defp scroll_key(:up, state), do: scroll_by(state, -1)
  defp scroll_key(:down, state), do: scroll_by(state, 1)
  defp scroll_key(:page_up, state), do: scroll_by(state, -page(state))
  defp scroll_key(:page_down, state), do: scroll_by(state, page(state))
  defp scroll_key(:home, state), do: schedule_render(%{state | scroll: 0, follow?: false})
  defp scroll_key(:end, state), do: schedule_render(%{state | follow?: true})

  defp scroll_by(state, delta) do
    scroll = (state.scroll + delta) |> min(state.max_scroll) |> max(0)
    follow? = if delta < 0, do: false, else: state.follow?
    schedule_render(%{state | scroll: scroll, follow?: follow?})
  end

  defp page(state), do: max(feed_h(state) - 1, 1)

  # The feed shares the height with the composer (bottom) and — when there are machine threads — a
  # one-row ORBIS rollup strip pinned at the top.
  defp feed_h(state), do: max(state.h - @box_rows - strip_rows(state), 1)

  defp strip_rows(%{rollup: %{summary: _}}), do: 1
  defp strip_rows(_state), do: 0

  defp refresh_size(state) do
    :termbox2_nif.tb_resize()
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # Newest-last (Slack order); a transient read failure keeps the last good frame (already reversed).
  defp poll_blocks(state) do
    Enum.reverse(Channel.machine_threads())
  rescue
    _ -> state.view.blocks
  catch
    :exit, _ -> state.view.blocks
  end

  defp schedule_render(%{render_armed?: true} = state), do: state

  defp schedule_render(state) do
    Process.send_after(self(), :render, @render_coalesce_ms)
    %{state | render_armed?: true}
  end

  # Render the ORBIS strip into the top rows (when present), the feed below it (bottom-anchored,
  # pinned to the newest while following), and the composer into the reserved bottom rows. One
  # render per frame.
  defp paint(state) do
    sh = strip_rows(state)
    feed_h = feed_h(state)
    rows = Transcript.render(state.view, %{x: 0, y: 0, w: state.w, h: @max_rows})
    max_scroll = max(length(rows) - feed_h, 0)
    scroll = if state.follow?, do: max_scroll, else: min(state.scroll, max_scroll)
    windowed = rows |> Enum.drop(scroll) |> Enum.take(feed_h)
    top_pad = List.duplicate([], max(feed_h - length(windowed), 0))

    strip_cells = strip_cells(state, sh)
    feed_cells = Board.rows_to_cells(top_pad ++ windowed, %{x: 0, y: sh, w: state.w, h: feed_h})
    box_cells = state |> composer_rows() |> Board.rows_to_cells(%{x: 0, y: sh + feed_h, w: state.w, h: @box_rows})

    Board.paint(strip_cells ++ feed_cells ++ box_cells)
    %{state | scroll: scroll, max_scroll: max_scroll, follow?: state.follow? or scroll >= max_scroll}
  end

  # The ORBIS rollup strip: the same styled summary line the sidebar panel paints, so the two never
  # drift, prefixed with a label. Absent when there are no machine threads.
  defp strip_cells(_state, 0), do: []

  defp strip_cells(%{rollup: %{summary: summary}, w: w}, sh) do
    row = [{"  ORBIS · ", :accent}] ++ Aleph.Panel.Orbis.summary_row(summary)
    Board.rows_to_cells([row], %{x: 0, y: 0, w: w, h: sh})
  end

  # The composer: a rule then the input line — the task text with a cursor in COMPOSE, a hint in
  # BROWSE.
  defp composer_rows(%{mode: :compose, input: "", w: w}) do
    [rule(w), [{"  ＋ new task — type and press Enter · Esc to browse", :dim}]]
  end

  defp composer_rows(%{mode: :compose, input: input, w: w}) do
    [rule(w), [{"  ＋ ", :accent}, {input, :normal}, {"▌", :accent}]]
  end

  defp composer_rows(%{mode: :browse, w: w}) do
    [rule(w), [{"  ── browse ──  j/k select · z read · Esc/i compose", :dim}]]
  end

  defp rule(w), do: [{String.duplicate("─", max(w, 1)), :separator}]

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
