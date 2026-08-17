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
  alias Aleph.Mouse
  alias Aleph.Panel
  alias Aleph.Sessions
  alias Aleph.Space
  alias Aleph.Terminal
  alias Aleph.View
  alias Funes.Bus
  alias Funes.Channel
  alias Funes.MCP.Spawn
  alias Funes.Staff
  alias Ghostty.KeyEvent
  alias Raxol.Core.Events.Event

  # Redraw cadence for tmux liveness + roster warmth, independent of Bus events.
  @tick_ms 500
  # Coalesce a burst of terminal events (pi streaming, tmux output) into ONE render on this
  # cadence, instead of rendering per-event. During streaming the embedded terminal fires
  # hundreds of events/sec; rendering each starves key casts queued behind them in the
  # mailbox. ~8ms ≈ 120fps — one frame of output latency, and terminal-event handling
  # becomes a cheap no-op once a render is armed, so the mailbox drains and input lands now.
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  # TB_INPUT_ESC (1) | TB_INPUT_MOUSE (4) = 5 (termbox2.h §309–313): keep ESC-sequence parsing AND
  # emit mouse events, which the Driver translates into Event{type: :mouse, data: %{x, y, button}}.
  @tb_input_esc_mouse 5

  # Stable identities for Tlön's two machine coworkers, so restarts reuse the same agents (no
  # collision with a project thread's harness). Both share the machine thread: pi always-on,
  # claude a lazy escalation spawned on first focus, so entering Tlön alone never drains the bucket.
  @machine_agent "pi-machine"
  @machine_claude_agent "claude-machine"

  # Kitty keyboard protocol: push flags + set disambiguate (CSI > 1 u) at init, pop (CSI < u)
  # at teardown. See the init comment for the full shifted-key round-trip.
  @kitty_enable "\e[>1u"
  @kitty_disable "\e[<u"

  @doc "Start the cockpit and block until the operator quits — the entry point `mix aleph.run` calls."
  @spec run() :: :ok
  def run do
    # Unlinked + monitored: a cockpit crash surfaces here as a clean DOWN, not a linked exit that
    # takes the task process down before it can restore the terminal.
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            restore_host_tty()
            # Capture a crashed exit — the alt-screen otherwise swallows it silently.
            log_crash(reason)
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
        # Trap exits so a crash anywhere — this server, or the linked Driver — runs terminate/2,
        # which restores the host tty (Kitty pop + tb_shutdown). Without this, a raise mid-callback
        # leaves the shell in alt-screen + mouse-reporting + Kitty mode until a manual `reset`.
        Process.flag(:trap_exit, true)
        :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
        :termbox2_nif.tb_set_input_mode(@tb_input_esc_mouse)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())
        # Watch every session terminal — the `s` verb AND the arbiter's autonomous spawn repaint
        # through this cockpit, whoever started them.
        Sessions.observe(self())

        # Enable Kitty keyboard disambiguate mode (CSI >1u) on the host tty so shift+enter etc.
        # arrive with modifiers intact (raxol's self-healed InputParser decodes \e[<cp>;<mods>u —
        # see mix.exs) instead of degrading to a bare \r. Popped in teardown; harmless on a
        # non-Kitty host (the push is simply ignored).
        IO.write(@kitty_enable)

        state =
          render(%{
            driver: driver,
            w: max(:termbox2_nif.tb_width(), 1),
            h: max(:termbox2_nif.tb_height(), 1),
            active_key: List.first(Space.all()).key,
            focused_id: nil,
            threads: [],
            subscribed_thread: nil,
            leader_pending?: false,
            input: nil,
            flash: nil,
            scrolls: %{},
            placements: [],
            render_scheduled?: false
          })

        Process.send_after(self(), :tick, @tick_ms)
        {:ok, state}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's tb_init enables DECCKM (application cursor keys), so arrows arrive as SS3 (ESC O A)
  # instead of CSI — raxol's InputParser only decodes CSI arrows, so under DECCKM :up/:down never
  # fired (only j/k worked). Reset on /dev/tty (the fd termbox drives) so arrows come through as CSI.
  defp normalize_cursor_keys do
    # Best-effort: if /dev/tty can't be written we simply keep termbox's default cursor-key mode.
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state) do
    # Use termbox's re-queried size (refresh_size/tb_resize), not the event's, so state.w/h never
    # exceeds what termbox will actually render at. The tick catches this too as a backstop.
    state = refresh_size(state)
    resize_focused_terminal(state)
    {:noreply, render(state)}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    # Any keypress clears a prior flash (a spawn/create result), so it shows until you act again.
    # `center_live?` and `composer_thread_id` are derived per keypress and handed to the keymap so
    # it knows whether to forward to the PTY / which thread `c` targets. They are NOT stored —
    # dropped on the way back; the cockpit keeps only `leader_pending?`.
    keymap_state =
      %{state | flash: nil}
      |> Map.put(:center_live?, center_terminal(state) != nil)
      |> Map.put(:composer_thread_id, composer_thread_id(state))

    {next, effect} = Keymap.handle(key, keymap_state)
    next = reset_scrolls(state, Map.drop(next, [:center_live?, :composer_thread_id]))
    apply_effect(effect, next)
  end

  # A wheel routes to whatever panel is under the cursor: the center terminal forwards to its PTY
  # or scrolls its scrollback (Aleph.Terminal.wheel/5), a scrollable list panel advances its offset
  # (clamped to its content height), anything else is ignored. Event coords are 1-based SGR;
  # `Mouse.to_cell/1` normalizes them to the 0-based cells the placement rects use.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: b}}}, state)
      when b in [:wheel_up, :wheel_down] do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}
    dispatch_wheel(Mouse.hit_panel(state.placements, x, y), b, x, y, state)
  end

  # A left PRESS routes to the panel under the cursor and asks it what that row selects — focus a
  # thread, switch a space — then repaints. Press only: the SGR release carries the same button,
  # and acting on both would double-fire (and re-hit re-laid-out placements after a space switch).
  # Non-selectable panels (Dossier/Stack/Tools, the center terminal) return nil → no-op.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left, action: :press}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}
    dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, state)
  end

  # Any other mouse event (release, right/middle button, motion) is not handled yet.
  def handle_cast({:dispatch, %Event{type: :mouse}}, state), do: {:noreply, state}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  @impl true
  def handle_info({tag, row}, state)
      when tag in [
             :message_posted,
             :fact_banked,
             :event_recorded,
             :issue_raised,
             :issue_resolved,
             :question_raised,
             :question_resolved,
             :thread_opened,
             :thread_closed,
             :thread_assigned,
             :session_started,
             :session_ended
           ] do
    desktop_notify(tag, row)
    {:noreply, render(state)}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    # A pending coalesced :render is now redundant (this tick paints); drop the flag so it no-ops.
    state = %{state | render_scheduled?: false}
    # Re-sync every tick so a missed SIGWINCH self-corrects: refresh_size re-queries via ioctl,
    # independent of any signal.
    state = refresh_size(state)
    # Re-fit the center PTY too: a terminal spawned between resizes starts at 80x24 and would
    # otherwise fill only part of the panel. Terminal.resize no-ops when size is unchanged.
    resize_focused_terminal(state)
    {:noreply, render(state)}
  end

  # Rendering per :updated event gave native-latency output but starved input during streaming
  # (the mailbox flooded with terminal events, each doing a full render, key casts queued behind).
  # Coalesce: arm one :render on a short timer; further events until it fires are cheap no-ops.
  def handle_info({Terminal, _pid, _event}, state), do: {:noreply, schedule_render(state)}

  # The coalesced render: clear the armed flag and paint. A :render that arrives with the
  # flag cleared (a tick or key cast already painted and dropped the flag) is a no-op — no
  # double render.
  def handle_info(:render, %{render_scheduled?: false} = state), do: {:noreply, state}
  def handle_info(:render, state), do: {:noreply, render(%{state | render_scheduled?: false})}

  # Trapped exit from the linked input Driver: the cockpit can't take keys anymore, so stop —
  # terminate/2 restores the tty on the way out.
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # Single source of truth for the cockpit's size. termbox only re-learns size in its poll path
  # (which aleph never calls), so tb_resize/0 (mix.exs defect #3) must sync it first or
  # tb_width()/tb_height() stay frozen at tb_init size.
  defp refresh_size(state) do
    :termbox2_nif.tb_resize()
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # Operator-relevant Bus events become native desktop notifications via an OSC 777 escape —
  # ghostty (Linux and macOS) raises it as a real notification, and only when unfocused (the
  # terminal owns focus policy). Best-effort: a host that ignores OSC 777 ignores the bytes.
  defp desktop_notify(tag, row) do
    with {title, body} <- Aleph.Notify.for_event(tag, row) do
      _ = File.write("/dev/tty", Aleph.Notify.osc(title, body))
    end

    :ok
  end

  defp dispatch_wheel(nil, _b, _x, _y, state), do: {:noreply, state}

  # The center terminal: forward to the embedded app if it tracks the mouse, else scroll scrollback.
  defp dispatch_wheel({Panel.Terminal, _data, rect}, b, x, y, state) do
    with term when is_pid(term) <- center_terminal(state),
         {dir, n} <- Mouse.wheel_of(b) do
      lx = clamp_cell(x - rect.x, rect.w)
      ly = clamp_cell(y - rect.y, rect.h)
      repaint_on_scroll(Terminal.wheel(term, dir, n, lx, ly), state)
    else
      _ -> {:noreply, state}
    end
  end

  # A scrollable list panel: advance its offset, clamped to its content height, and repaint. A
  # non-scrollable panel under the wheel (Spaces, a non-center frame) is a no-op.
  defp dispatch_wheel({panel, data, rect}, b, _x, _y, state),
    do: scroll_wheel(Panel.scrollable?(data), panel, data, rect, b, state)

  defp scroll_wheel(true, panel, data, rect, b, state) do
    {dir, n} = Mouse.wheel_of(b)
    content_h = Panel.content_height(panel, data, rect.w)
    next = Mouse.clamp_offset((state.scrolls[panel] || 0) + Terminal.scroll_delta(dir, n), content_h, rect.h)
    {:noreply, render(%{state | scrolls: Map.put(state.scrolls, panel, next)})}
  end

  defp scroll_wheel(false, _panel, _data, _rect, _b, state), do: {:noreply, state}

  defp clamp_cell(v, extent), do: v |> max(0) |> min(max(extent - 1, 0))

  defp repaint_on_scroll(:scrolled, state), do: {:noreply, render(state)}
  defp repaint_on_scroll(:forwarded, state), do: {:noreply, state}

  defp dispatch_click(nil, _x, _y, state), do: {:noreply, state}

  # Clicking the center terminal: forwarded to the PTY when the embedded program tracks the
  # mouse — tmux (`mouse on`) selects the pane/window under the cursor, a TUI hit-tests its own
  # regions. Untracked (a plain shell) → no-op; the terminal already owns the keys when live.
  defp dispatch_click({Panel.Terminal, _data, rect}, x, y, state) do
    with term when is_pid(term) <- center_terminal(state) do
      Terminal.click(term, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
    end

    {:noreply, state}
  end

  defp dispatch_click({panel, data, rect}, _x, y, state), do: apply_pick(Panel.pick(panel, data, rect, y - rect.y), state)

  defp apply_pick(nil, state), do: {:noreply, state}

  # Selecting a thread by click swaps the focused thread (and thus the center's terminal) — no
  # focus flag to clear in the tmux-style model.
  defp apply_pick({:focus_thread, id}, state) do
    next = reset_scrolls(state, %{state | focused_id: id, flash: nil})
    {:noreply, render(next)}
  end

  defp apply_pick({:switch_space, key}, state) do
    next = reset_scrolls(state, %{state | active_key: key, flash: nil})
    {:noreply, render(next)}
  end

  # Reset scroll offsets when the context they're relative to changes. A space switch swaps every
  # panel, so all offsets go; a focus change only swaps the thread-specific panels (Dossier,
  # Conversation), so just those. Function-head dispatch on what changed — house rule.
  defp reset_scrolls(%{active_key: a}, %{active_key: a2} = next) when a != a2, do: %{next | scrolls: %{}}

  defp reset_scrolls(%{focused_id: f}, %{focused_id: f2} = next) when f != f2,
    do: %{next | scrolls: Map.drop(next.scrolls, [Panel.Dossier, Panel.Conversation])}

  defp reset_scrolls(_prev, next), do: next

  # State transitions live in the pure `Aleph.Keymap`; the Cockpit only runs the side effect it
  # asks for — repaint, quit, or forward a key to the focused terminal.
  defp apply_effect(:repaint, state), do: {:noreply, render(state)}
  defp apply_effect(:none, state), do: {:noreply, state}
  defp apply_effect(:quit, state), do: quit(state)

  # A focused key goes to the focused session's embedded terminal: encode it as a Ghostty.KeyEvent
  # and hand it to the emulator, which writes the right bytes straight to the PTY — one native
  # keystroke, no shell-out. An unmappable key is dropped rather than misdelivered.
  defp apply_effect({:forward, key}, state) do
    with %KeyEvent{} = event <- ghostty_key(key),
         term when is_pid(term) <- center_terminal(state) do
      Terminal.send_key(term, event)
    end

    {:noreply, state}
  end

  # The `n` verb landed: open the thread, focus it, AND spawn a session onto it in one motion —
  # a new thread is a new piece of work, so `n` starts working on it. A bad title just flashes.
  defp apply_effect({:create_thread, title}, state) do
    case Channel.open_thread(%{title: title}) do
      {:ok, thread} -> {:noreply, render(%{state | focused_id: thread.id, flash: spawn_onto(thread.id, state)})}
      {:error, _changeset} -> {:noreply, render(%{state | flash: "couldn't create “#{title}”"})}
    end
  end

  # The `c` verb landed: post the composer's body to the focused thread AS THE OPERATOR (config
  # `:funes, :operator`), so a posted message is the human's voice, not an agent's. The Bus
  # announce repaints the chorus live, so the message lands visibly; a failure flashes in the footer.
  defp apply_effect({:post_message, thread_id, body}, state) do
    operator = Application.get_env(:funes, :operator, "andrew")

    case Channel.post(%{thread_id: thread_id, author: operator, body: body}) do
      {:ok, _message} -> {:noreply, render(%{state | flash: "posted"})}
      {:error, _changeset} -> {:noreply, render(%{state | flash: "couldn't post — is the thread open?"})}
    end
  rescue
    e -> {:noreply, render(%{state | flash: "post failed: #{Exception.message(e)}"})}
  catch
    :exit, reason -> {:noreply, render(%{state | flash: "post failed: #{inspect(reason)}"})}
  end

  # The `Enter` verb landed: enter-or-spawn on the focused thread. The result flashes in the footer.
  defp apply_effect({:enter_or_spawn, thread_id}, state),
    do: {:noreply, render(%{state | flash: enter_or_spawn(thread_id, state)})}

  # The `o` verb landed: summon the claude window into the tlon tmux session if it doesn't
  # exist (the lazy escalation — this is claude's ONLY spawn site), else cycle tmux's windows.
  # tmux is the source of truth for what's up, so nothing here can drift from what's on screen.
  defp apply_effect(:toggle_pane, state), do: {:noreply, render(%{state | flash: toggle_claude_window()})}

  # `enter_or_spawn`: if the focused thread already has a live session, it's already the center —
  # nothing to do (you're already working there). Otherwise spawn one onto it. The replacement for
  # the old bare `s` verb — one `spawn_onto/2` path, reached via `n` (new thread) or `Enter` (existing).
  defp enter_or_spawn(thread_id, state) do
    case Sessions.terminal(thread_id) do
      pid when is_pid(pid) -> "already live — type to use it, Ctrl+Space for aleph"
      nil -> spawn_onto(thread_id, state)
    end
  end

  # Spawn a harness as an embedded terminal on this thread: mint identity IN-PROCESS
  # (Funes.MCP.Spawn.join — aleph is the serving node) and start an Aleph.Terminal that runs the
  # launcher with the FUNES_* env sourced (and TERM set, so the harness produces colour). One
  # native PTY per thread, rendered in the center. A raise/exit becomes a flash, never a crash.
  defp spawn_onto(thread_id, state) do
    agent = Application.get_env(:aleph, :spawn_agent, "pi")
    {cols, rows} = center_dims(state)

    case Spawn.join(thread_id, agent) do
      {:ok, %{exports: exports}} ->
        case Sessions.spawn_harness(thread_id, exports, cols: cols, rows: rows) do
          {:ok, _pid} -> "session live — type to use it, Ctrl+Space for aleph"
          {:error, reason} -> "spawn failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        "spawn failed: #{inspect(reason)}"
    end
  rescue
    e -> "spawn crashed: #{Exception.message(e)}"
  catch
    :exit, reason -> "spawn crashed: #{inspect(reason)}"
  end

  # aleph key event → Ghostty.KeyEvent (public + tested: a missing mapping silently drops a key).
  @doc false
  def ghostty_key(%{key: :char, char: c} = ev),
    do: %KeyEvent{key: char_key(c), utf8: c, mods: mods(ev), unshifted_codepoint: unshifted_codepoint(c)}

  def ghostty_key(%{key: :up} = ev), do: %KeyEvent{key: :arrow_up, mods: mods(ev)}
  def ghostty_key(%{key: :down} = ev), do: %KeyEvent{key: :arrow_down, mods: mods(ev)}
  def ghostty_key(%{key: :left} = ev), do: %KeyEvent{key: :arrow_left, mods: mods(ev)}
  def ghostty_key(%{key: :right} = ev), do: %KeyEvent{key: :arrow_right, mods: mods(ev)}

  def ghostty_key(%{key: k} = ev)
      when k in [:enter, :tab, :backspace, :delete, :escape, :space, :home, :end, :page_up, :page_down],
      do: %KeyEvent{key: k, mods: mods(ev)}

  def ghostty_key(_key), do: nil

  # a-z (and A-Z → the lowercase key + a shift mod via utf8), 0-9 → :digit_N; anything else is
  # carried by utf8 alone under :unidentified.
  defp char_key(<<cp>>) when cp in ?a..?z, do: String.to_existing_atom(<<cp>>)
  defp char_key(<<cp>>) when cp in ?A..?Z, do: String.to_existing_atom(<<cp + 32>>)
  defp char_key(<<cp>>) when cp in ?0..?9, do: String.to_existing_atom("digit_#{<<cp>>}")
  defp char_key(_c), do: :unidentified

  # The Kitty encoder needs the unshifted codepoint to build \e[<cp>;<mods>u for a modified
  # printable (ctrl+v → \e[118;5u); without it modifiers are dropped (ctrl+v → "v"). Letters use
  # their lowercase codepoint. KNOWN LIMIT: a shifted symbol (shift+2 → "@") can't be recovered
  # here (the host keyboard layout is gone by this layer) — no current binding hits that path.
  defp unshifted_codepoint(c) do
    c |> String.downcase() |> String.to_charlist() |> List.first() || 0
  end

  defp mods(ev) do
    [{:ctrl, ev[:ctrl]}, {:alt, ev[:alt]}, {:shift, ev[:shift]}]
    |> Enum.filter(fn {_mod, on?} -> on? end)
    |> Enum.map(fn {mod, _} -> mod end)
  end

  # Arm one coalesced render if none is armed. The first terminal event in a burst schedules
  # the :render; the rest see the flag set and do nothing — the single :render picks up the
  # latest terminal state, whatever arrived in the ~8ms window.
  defp schedule_render(%{render_scheduled?: true} = state), do: state

  defp schedule_render(state) do
    Process.send_after(self(), :render, @render_coalesce_ms)
    %{state | render_scheduled?: true}
  end

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
      terminal: terminal_read(state, focused),
      machine: machine_read(state),
      stack: stack_read(state.active_key),
      scrolls: state.scrolls,
      input: state.input,
      flash: state.flash,
      leader_pending?: state.leader_pending?
    }

    placements = View.compose(reads, state.w, state.h)

    placements
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    %{state | placements: placements}
  end

  defp focused(state), do: focused_thread(state.threads, state.focused_id)

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The Sessions center: the focused thread's Aleph.Terminal render_state (Ghostty's live cells
  # + cursor), read fresh; no session → the placeholder. `:no_session` elsewhere.
  defp terminal_read(%{active_key: :sessions} = state, _focused) do
    state |> center_terminal() |> render_state_of()
  end

  defp terminal_read(_state, _focused), do: :no_session

  # The Tlön center's read: the embedded tmux client (find-or-created on entry). tmux owns the
  # windows inside it; aleph just renders the attached client.
  defp machine_read(%{active_key: :tlon}), do: render_state_of(machine_terminal())
  defp machine_read(_state), do: :no_session

  defp render_state_of(nil), do: :no_session
  defp render_state_of(term), do: Terminal.render_state(term)

  # The terminal that owns the keys, by space: Sessions → the focused thread's session; Tlön →
  # the embedded tmux client. nil elsewhere.
  defp center_terminal(%{active_key: :sessions} = state), do: state |> focused() |> terminal_for()
  defp center_terminal(%{active_key: :tlon}), do: machine_terminal()
  defp center_terminal(_state), do: nil

  # The thread `c` composes onto, derived per keypress (like center_live?): the focused project
  # thread in Comms/Sessions; in Tlön the MACHINE thread — the operator working the box posts to
  # the machine coworker, never a stale project thread id carried over from Comms. nil (no thread)
  # makes `c` a no-op.
  defp composer_thread_id(%{active_key: :tlon}), do: machine_thread_id()
  defp composer_thread_id(state), do: state.focused_id

  defp machine_thread_id do
    case Channel.machine_thread() do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp terminal_for(nil), do: nil
  defp terminal_for(%{id: id}), do: Sessions.terminal(id)

  # The STACK/TOOLS reads are only gathered on Tlön (git log + version probes are wasted elsewhere).
  defp stack_read(:tlon), do: %{commits: Aleph.Stack.commits(), tools: Aleph.Stack.tools()}
  defp stack_read(_key), do: %{commits: [], tools: []}

  # The Tlön machine coworker: a pi session working ON the box on a persistent "machine" thread
  # (so its work is triageable). pi by design — Tlön is meta/machine work, claude stays the
  # deliberate escalation (AGENTS.md routing). Spawned once, reused via registry lookup.
  defp machine_terminal do
    case Sessions.terminal(:machine) do
      pid when is_pid(pid) -> pid
      nil -> spawn_machine_coworker()
    end
  end

  # The tlon tmux session name — tmux is a first-class stack citizen here: the Tlön center is a
  # real `tmux attach`, so the machine workspace gets the user's tmux config, mouse, windows,
  # and resurrect/continuum persistence, and it SURVIVES aleph restarts.
  @tlon_session "tlon"

  # Find-or-create the machine coworker's identity, then spawn the Tlön center: an embedded
  # tmux client attached to the standing session (pi as window 0 if absent) — an aleph restart
  # re-attaches to the running pi instead of spawning another.
  defp spawn_machine_coworker do
    with {:ok, exports} <- machine_exports(@machine_agent),
         # kitty: false — tmux wants its Ctrl+B prefix as legacy \x02, not CSI-u (see Terminal.init).
         {:ok, pid} <- Sessions.spawn_harness(:machine, exports, launcher: tlon_launcher(exports), kitty: false) do
      pid
    else
      _error -> nil
    end
  end

  @doc false
  # `new-session -A` = attach-or-create; pi becomes window 0's command on first creation only.
  # tmux runs that command in the SERVER's environment, not the client's, so `-e` forwards each
  # FUNES_* export into the new session (ignored on attach, so only first creation wires it — an
  # unwired `tlon` session must be killed to re-wire).
  def tlon_launcher(exports) do
    pi = Application.get_env(:aleph, :spawn_launcher, "mise exec -- pi")
    env_flags = exports |> env_pairs() |> Enum.map_join(" ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)
    "tmux new-session -A -s #{@tlon_session} #{env_flags} '#{pi}'"
  end

  # The `export KEY="VALUE"` lines of a FUNES_* exports block as `{key, value}` pairs.
  defp env_pairs(exports) do
    ~r/export (\w+)="([^"]*)"/
    |> Regex.scan(exports)
    |> Enum.map(fn [_, k, v] -> {k, v} end)
  end

  # POSIX single-quote: escape embedded quotes as '\'' so the value survives the shell verbatim.
  defp sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # `o`: claude window absent → summon it; present → cycle tmux's windows. Asking tmux (not
  # cockpit state) means this can't drift from what's actually on screen.
  defp toggle_claude_window do
    case System.cmd("tmux", ["list-windows", "-t", @tlon_session, "-F", "\#{window_name}"], stderr_to_stdout: true) do
      {out, 0} -> toggle_claude_window(String.split(out, "\n", trim: true))
      {_out, _code} -> "the tlon tmux session isn't up — enter Tlön to start it"
    end
  end

  defp toggle_claude_window(windows) do
    if "claude" in windows, do: cycle_tlon_window(), else: summon_claude_window()
  end

  defp cycle_tlon_window do
    System.cmd("tmux", ["next-window", "-t", @tlon_session], stderr_to_stdout: true)
    nil
  end

  # Claude joins the SAME machine thread as pi (two voices, one thread) as a new tmux window,
  # carrying its own identity exports (claude-machine). No FUNES_TOKEN is frozen into the env —
  # headersHelper mints a fresh token per connect, so it survives a restart/model change/secret rotation.
  defp summon_claude_window do
    launcher = Application.get_env(:aleph, :machine_claude_launcher, "mise run funes:claude")

    case machine_exports(@machine_claude_agent) do
      {:ok, exports} ->
        script = exports <> "\nexec env --default-signal " <> launcher

        case System.cmd("tmux", ["new-window", "-t", @tlon_session, "-n", "claude", script], stderr_to_stdout: true) do
          {_out, 0} -> "claude summoned — Ctrl+Space o cycles pi ⇄ claude"
          {out, _code} -> "claude window failed: #{String.trim(out)}"
        end

      error ->
        "claude spawn failed: #{inspect(error)}"
    end
  rescue
    e -> "claude spawn crashed: #{Exception.message(e)}"
  catch
    :exit, reason -> "claude spawn crashed: #{inspect(reason)}"
  end

  # Resolve a machine pane's FUNES_* exports by find-or-create: reuse the latest open machine
  # thread (joining it as `agent`) if one exists, else open a fresh `scope: "machine"` thread.
  defp machine_exports(agent) do
    case Channel.machine_thread() do
      %{id: id} ->
        with {:ok, %{exports: e}} <- Spawn.join(id, agent), do: {:ok, e}

      nil ->
        with {:ok, %{exports: e}} <- Spawn.env("Tlön", agent, mandate: "machine", scope: "machine"), do: {:ok, e}
    end
  end

  # Keep the center session's PTY sized to the center region so it reflows with the window. An
  # approximation of the center rect (View lays out left ¼ / center ½ / right ¼, inset by a frame);
  # the terminal reflows on every window resize.
  defp resize_focused_terminal(state) do
    with term when is_pid(term) <- center_terminal(state) do
      {cols, rows} = center_dims(state)
      Terminal.resize(term, cols, rows)
    end
  end

  defp center_dims(%{w: w, h: h}) do
    {max(div(w, 2) - 4, 20), max(h - 6, 5)}
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

  # terminate/2 (not the quit path) owns the tty restore, so it runs on a normal quit AND on a
  # crash in any callback — the reason init traps exits.
  defp quit(state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state), do: teardown(state)

  defp teardown(state) do
    # Pop Kitty while still ON the alt screen (the spec gives main and alternate screens
    # INDEPENDENT keyboard-flag stacks, so the pop must land on the screen the push landed on).
    # Straight to /dev/tty, not stdout — the io server may already be winding down on a crash.
    _ = File.write("/dev/tty", @kitty_disable)

    # Each step in its own try: a wedged Driver stop (it can exceed its 500ms) must never skip
    # tb_shutdown — that skip leaves the shell in alt-screen + mouse-reporting, needing `reset`.
    try do
      if is_pid(state.driver) and Process.alive?(state.driver),
        do: GenServer.stop(state.driver, :normal, 500)
    catch
      _, _ -> :ok
    end

    try do
      :termbox2_nif.tb_shutdown()
    catch
      _, _ -> :ok
    end

    # Back on the MAIN screen now — final belt-and-braces restore (see restore_host_tty/0).
    restore_host_tty()
  end

  # Force-disarm everything a dead cockpit could have left armed: Kitty pop (no-op on an empty
  # stack), mouse reporting off, leave alt screen, show cursor. Idempotent — run/0 also calls this
  # after a DOWN, so even a killed GenServer leaves a working shell, not `;5u` keystroke garbage.
  defp restore_host_tty do
    _ = File.write("/dev/tty", @kitty_disable <> "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h")
    :ok
  end

  @doc false
  # A formatted crash report for a non-normal DOWN reason, or nil for a clean quit — so a normal
  # operator quit doesn't spam the log. Pure; the IO is in log_crash/1.
  @spec crash_report(term()) :: String.t() | nil
  def crash_report(reason) when reason in [:normal, :shutdown], do: nil
  def crash_report({:shutdown, _}), do: nil
  def crash_report(reason), do: Exception.format_exit(reason)

  # Append a crashed exit to the crash log and echo it to stderr after the tty is restored, so it
  # doesn't get swallowed by the alt-screen. Best-effort: a log write failure never masks the crash.
  defp log_crash(reason) do
    case crash_report(reason) do
      nil ->
        :ok

      report ->
        Aleph.CrashLog.append("aleph crash", report)
        IO.puts(:stderr, "aleph crashed (logged to #{Aleph.CrashLog.path()}):\n#{report}")
        file_crash_issue(report)
    end
  rescue
    _ -> :ok
  end

  @doc false
  @spec crash_summary(String.t()) :: String.t()
  def crash_summary(report) do
    report |> String.split("\n", trim: true) |> List.first("a cockpit crash") |> String.slice(0, 120)
  end

  # A crashed cockpit files a funes issue on the machine thread — its own failures become tracked,
  # triageable work in the system it renders, not just a log line. Deduped against the thread's open
  # issues so a crash loop files one, not a hundred. Best-effort: no funes (down, or the crash took
  # it too) just means the crash log is the only record.
  defp file_crash_issue(report) do
    summary = "aleph crashed: " <> crash_summary(report)

    with %{id: id} = thread <- Channel.machine_thread(),
         false <- crash_issue_open?(thread, summary) do
      Funes.Dossier.raise_issue(%{thread_id: id, summary: summary, evidence: report, found_by: "aleph"})
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp crash_issue_open?(thread, summary) do
    thread |> Funes.Dossier.open_issues_for_thread() |> Enum.any?(&(&1.summary == summary))
  end
end
