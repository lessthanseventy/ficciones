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
  alias Aleph.Profiles
  alias Aleph.Transcript
  alias Funes.Channel
  alias Raxol.Core.Events.Event

  @poll_ms 700
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  @tb_input_esc_mouse 5
  @wheel_lines 3
  @max_rows 10_000
  # Rows reserved at the bottom for the composer: a blank spacer, a rule, and the input line.
  @box_rows 3
  # Left/right gutter columns — the feed, strip, and composer inset from the pane edges to breathe.
  @pad_x 2

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

  # Manual list nav takes control from tail-follow — else the next poll (which re-snaps the
  # selection to the newest while `follow?`) yanks the cursor back to the bottom mid-browse.
  defp browse_list(:next, state), do: {:noreply, host_view(%{state | follow?: false}, :down)}
  defp browse_list(:prev, state), do: {:noreply, host_view(%{state | follow?: false}, :up)}
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

  # Submit the composer text: a reply into the zoomed thread, else a fresh thread/task. Failures
  # just clear the box rather than crash the tab.
  defp submit(%{input: input} = state) do
    text = String.trim(input)
    if text == "", do: state, else: do_submit(state, text)
  rescue
    _ -> %{state | input: ""}
  catch
    :exit, _ -> %{state | input: ""}
  end

  # A zoomed thread makes the composer a REPLY box (the "reply = read context" model); with nothing
  # zoomed it opens a new thread.
  defp do_submit(%{view: %{zoom: nil}} = state, text), do: submit_new(state, text)
  defp do_submit(%{view: %{zoom: thread_id}} = state, text), do: submit_reply(state, thread_id, text)

  # Reply straight into the zoomed thread and self-wake its lead/@-mentions. Unlike a new thread
  # there's no cockpit staffing to defer to: the cockpit only wakes for messages on its own bus,
  # which it never sees from our cross-process DB post — so we always wake here. Stays zoomed +
  # follows so the reply lands in view.
  defp submit_reply(state, thread_id, text) do
    author = operator()
    Channel.post(%{thread_id: thread_id, author: author, body: text})
    wake_mentions(author, text, thread_id)
    %{state | input: "", follow?: true}
  end

  # Kick off a new thread/task: open a machine-scope funes thread titled by the text, post it as the
  # operator, wake any @-mentioned coworker, then clear and land at the bottom so the fresh episode
  # is in view.
  defp submit_new(state, text) do
    author = operator()

    case Channel.open_thread(%{title: text, scope: "machine"}) do
      {:ok, thread} ->
        Channel.post(%{thread_id: thread.id, author: author, body: text})

        case stage_lead(thread.id, text) do
          # The cockpit (a SEPARATE beam) spawns a dedicated `t<id>` session for any WORKER lead
          # (claude or pi — Slice A) and injects the opening turn ITSELF (`ensure_thread_sessions`).
          # Waking the standing coworker from here too is the "both claudes answered" duplicate — so
          # only wake from here for a lead the cockpit won't staff (a meta/unknown lead).
          {:ok, lead} -> if !cockpit_staffs?(lead), do: wake_mentions(author, text, thread.id)
          {:error, reason} -> note_no_lead(thread.id, reason)
        end

        %{state | input: "", follow?: true}

      _ ->
        %{state | input: ""}
    end
  end

  defp operator, do: Application.get_env(:funes, :operator, "andrew")

  # Staff the picked coworker as the new thread's lead: the composer text's first @-mention, else
  # the operator's persisted override, else the LIVE world roster's builder/lead. Returns
  # `{:ok, handle}` on a real staffing, `{:error, reason}` when nobody resolves or `assign_lead`
  # can't bind the handle (an unregistered coworker) — the caller surfaces it instead of opening a
  # leaderless, silent thread. The thread + opening message are already durable regardless.
  defp stage_lead(thread_id, text) do
    roster = active_roster()
    default = Config.default_coworker_override() || Staffing.default_coworker(roster)

    case Staffing.pick_coworker(text, default, roster) do
      nil -> {:error, :no_coworker}
      handle -> stage(thread_id, handle)
    end
  end

  # `Funes.assign_lead/2` returns `{:error, :no_agent}` for a handle that was never registered — a
  # no-op, not a raise — so we check it rather than assume success.
  defp stage(thread_id, handle) do
    case Funes.assign_lead(thread_id, handle) do
      {:error, reason} -> {:error, reason}
      _ -> {:ok, handle}
    end
  end

  # Surface a leaderless thread in the feed itself (the operator sees WHY it's quiet) rather than
  # silently eating the message. Best-effort: a post failure just leaves the thread quiet.
  defp note_no_lead(thread_id, reason) do
    Channel.post(%{
      thread_id: thread_id,
      author: "aleph",
      body: "⚠ no coworker staffed (#{inspect(reason)}) — nobody is listening on this thread yet." <> no_lead_hint(reason)
    })

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # `:no_coworker` = the worker-only default resolved nobody (Slice B: the meta surveyor never
  # leads) — tell the operator the fix, not just the symptom.
  defp no_lead_hint(:no_coworker), do: " Add a worker (builder/planner/reviewer/…) to the world's roster."
  defp no_lead_hint(_reason), do: ""

  # Does the cockpit spawn a per-thread `t<id>` session for this lead (so it owns the opening turn
  # and we must NOT also wake here)? Mirrors `Aleph.Cockpit.leaf_staffed?/2`: any WORKER roster
  # lead — claude or pi harness — gets its own leaf window now (Slice A); only a meta (surveyor)
  # or roster-unknown lead is still woken from here.
  # Against `active_roster/0` (the single World in Slice 1) — a later multi-world Loop would thread
  # this from the thread's own world instead.
  defp cockpit_staffs?(lead), do: lead in Profiles.leaf_handles(active_roster())

  # The active World's roster, read STRAIGHT from funes (not via `Space`/`Aleph.Worlds`): this is
  # the machine-chat reader beam — it never starts aleph's supervision tree, so the `Aleph.Worlds`
  # cache GenServer isn't here and `Space.first_world/0` would degrade to a hardcoded stand-in whose
  # builder handle was never registered as an agent. Funes-down / no world → `[]` (nobody wakes).
  defp active_roster do
    case live_world() do
      %{roster: [_ | _] = roster} -> roster
      _ -> []
    end
  end

  # The first live funes world (Slice 1: the single machine World). A plain `Repo.all` under the
  # hood — works in any beam funes booted in, unlike the cockpit-only `Aleph.Worlds` cache.
  defp live_world do
    case Funes.Worlds.all() do
      [world | _] -> world
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Which per-thread window a reply's wake must land on — mirrors `Aleph.Cockpit.delivery_target/3`.
  # A worker-led STAFFED leaf (claude or pi — Slice A) runs the episode in its own `t<id>` window,
  # so its reply must reach THAT session, not the lead's standing handle→window slot. The standing
  # thread has no `t<id>` window, so the probe returns nil and routing falls back to the standing
  # window — the same standing-vs-leaf split the cockpit makes. A reply is always past the opening
  # turn (no mid-spawn `:skip` gate needed): a live window suffices. Meta/no-lead threads never get
  # a `t<id>`.
  defp staffed_window(lead, thread_id) do
    if cockpit_staffs?(lead), do: live_leaf_window(thread_id)
  end

  # The leaf's live window NAME for `thread_id`: the `@funes_thread`-stamped window (Slice C's
  # routing map, read from tmux itself), else the legacy `t<id>` name (a pre-C window). nil when
  # the leaf has no window. ($TMUX points at the world's private server, and each world's server
  # hosts exactly one session (C2.2: `w<id>`) — so a bare `tmux` (no `-t session:`) resolves
  # against the CURRENT session and never needs to know the id.)
  defp live_leaf_window(thread_id) do
    case System.cmd("tmux", ["list-windows", "-F", "\#{window_name}\t\#{@funes_thread}"], stderr_to_stdout: true) do
      {out, 0} ->
        rows =
          out
          |> String.split("\n", trim: true)
          |> Enum.map(&String.split(&1, "\t", parts: 2))

        Enum.find_value(rows, fn
          [name, tid] -> if tid == "#{thread_id}", do: name
          _ -> nil
        end) ||
          Enum.find_value(rows, fn
            [name | _] -> if name == "t#{thread_id}", do: name
          end)

      _ ->
        nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  # Wake each @-mentioned coworker by injecting the message as a turn into its tmux window — the same
  # send-keys the cockpit does, but from here (our post is on our own bus, which the cockpit can't
  # see). $TMUX points at the world's server, and `-t <window>` (no session prefix) resolves against
  # the current session, same reasoning as `window_live?/1`.
  defp wake_mentions(author, body, thread_id) do
    lead = safe_thread_lead(thread_id)
    opts = [lead: lead, staffed_window: staffed_window(lead, thread_id)]

    for {window, text} <- Mention.route(%{author: author, body: body, thread_id: thread_id}, opts, active_roster()) do
      System.cmd("tmux", ["send-keys", "-t", window, "-l", text], stderr_to_stdout: true)
      System.cmd("tmux", ["send-keys", "-t", window, "Enter"], stderr_to_stdout: true)
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
    cw = content_w(state)
    rows = Transcript.render(state.view, %{x: 0, y: 0, w: cw, h: @max_rows})
    max_scroll = max(length(rows) - feed_h, 0)
    scroll = if state.follow?, do: max_scroll, else: min(state.scroll, max_scroll)
    windowed = rows |> Enum.drop(scroll) |> Enum.take(feed_h)
    top_pad = List.duplicate([], max(feed_h - length(windowed), 0))

    strip_cells = strip_cells(state, sh)
    feed_cells = Board.rows_to_cells(top_pad ++ windowed, %{x: @pad_x, y: sh, w: cw, h: feed_h})
    box_cells = state |> composer_rows(cw) |> Board.rows_to_cells(%{x: @pad_x, y: sh + feed_h, w: cw, h: @box_rows})

    Board.paint(strip_cells ++ feed_cells ++ box_cells)
    %{state | scroll: scroll, max_scroll: max_scroll, follow?: state.follow? or scroll >= max_scroll}
  end

  # The feed/composer content width: the pane less a gutter on each side.
  defp content_w(state), do: max(state.w - 2 * @pad_x, 1)

  # The ORBIS rollup strip: the same styled summary line the sidebar panel paints, so the two never
  # drift, prefixed with a label. Absent when there are no machine threads.
  defp strip_cells(_state, 0), do: []

  defp strip_cells(%{rollup: %{summary: summary}} = state, sh) do
    row = [{"ORBIS · ", :accent}] ++ Aleph.Panel.Leaves.summary_row(summary)
    Board.rows_to_cells([row], %{x: @pad_x, y: 0, w: content_w(state), h: sh})
  end

  # The composer: a blank spacer, a rule, then the input line — the task/reply text with a cursor in
  # COMPOSE, a hint in BROWSE. A zoomed thread turns the prompt into a reply into that thread.
  defp composer_rows(%{mode: :browse}, cw) do
    [[], rule(cw), [{"── browse ──  j/k select · z read · Esc/i compose", :dim}]]
  end

  defp composer_rows(%{mode: :compose, input: ""} = state, cw) do
    [[], rule(cw), [{compose_hint(state), :dim}]]
  end

  defp composer_rows(%{mode: :compose, input: input} = state, cw) do
    [[], rule(cw), [{compose_glyph(state), :accent}, {input, :normal}, {"▌", :accent}]]
  end

  # The empty-box prompt and the leading glyph both flip to a reply when a thread is zoomed.
  defp compose_hint(state) do
    case reply_title(state) do
      nil -> "＋ new task — type and press Enter · Esc to browse"
      title -> "↳ reply to #{title} — type and press Enter · Esc to browse"
    end
  end

  defp compose_glyph(state), do: if(reply_title(state), do: "↳ ", else: "＋ ")

  # The zoomed thread's title, or nil when nothing is zoomed (a new-task composer).
  defp reply_title(%{view: %{zoom: nil}}), do: nil

  defp reply_title(%{view: %{zoom: tid, blocks: blocks}}) do
    case Enum.find(blocks, &match?(%{thread: %{id: ^tid}}, &1)) do
      %{thread: %{title: title}} -> title || "untitled"
      _ -> nil
    end
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
