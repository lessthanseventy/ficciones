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
  alias Aleph.Profile
  alias Aleph.Profiles
  alias Aleph.Sessions
  alias Aleph.Space
  alias Aleph.Terminal
  alias Aleph.View
  alias Funes.Bus
  alias Funes.Channel
  alias Funes.Dossier
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

  # Stable identity for Tlön's machine coworker, so restarts reuse the same agent (no collision with
  # a project thread's harness). pi is window 0; any other window (a claude, a shell) the operator
  # opens with tmux's own keys (Ctrl+B c) — aleph renders them as tabs, it doesn't spawn them.
  @machine_agent "pi-machine"
  # The Tlön Claude-Code window's identity — joins the SAME machine thread as @machine_agent so the
  # two coordinate as ordinary funes agents (post_message back and forth), never a merged identity.
  @claude_agent "claude-machine"

  # The tlon tmux session name — tmux is a first-class stack citizen here: the Tlön center is a real
  # `tmux attach`, so the machine workspace gets mouse, windows, and copy-mode, and it SURVIVES
  # aleph restarts. It runs on its OWN tmux server though (`tmux -L aleph-tlon`, config from the
  # profile's persistence-free tmux.conf — Aleph.Profiles.socket/1), NOT the user's default server:
  # there resurrect/continuum would restore a torn-down coworker with stale identity/env.
  @tlon_session "tlon"

  # Tlön probe cadence: the Stack/Health reads fork subprocesses (git ×~6, nix-env, df, tmux)
  # and open a TCP probe — far too heavy to run per render (a streaming terminal coalesces to
  # ~125 renders/sec, and one nix-env alone exceeds the whole 8ms window; renders serialized
  # and starved input). Probes are CACHED in cockpit state and refreshed at most this often,
  # on the tick; every other render (keys, Bus events, terminal frames) reads the cache.
  @probe_ms 2_000

  # A failed machine-coworker spawn must not retry on every render (materialise + tmux
  # new-session per frame = a spawn storm whenever the coworker can't start). Back off.
  @machine_spawn_backoff_ms 5_000

  # Crash recovery (see run/0): relaunch the cockpit in place after a crash, but give up after
  # @resurrect_max_fails crashes in a row so a persistent bad state can't spin the terminal. A run
  # that survived @resurrect_healthy_ms is treated as healthy — its next crash starts the count over.
  @resurrect_max_fails 3
  @resurrect_healthy_ms 5_000

  # The funes identity the Tlön pi needs to wire its MCP client (`${FUNES_MCP_URL}` in the profile's
  # mcp.json + the bearer minted for FUNES_THREAD/FUNES_AUTHOR). Carried into the tmux SESSION env so
  # it survives a respawn — see funes_identity_flags/0.
  @funes_identity_env ~w(FUNES_MCP_URL FUNES_THREAD FUNES_AUTHOR FUNES_DB)

  # The empty Stack shape non-Tlön spaces (and a not-yet-probed Tlön) render.
  @empty_stack %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []}

  # Kitty keyboard protocol: push flags + set disambiguate (CSI > 1 u) at init, pop (CSI < u)
  # at teardown. See the init comment for the full shifted-key round-trip.
  @kitty_enable "\e[>1u"
  @kitty_disable "\e[<u"

  # Bracketed paste: enable (\e[?2004h) at init so ghostty wraps a paste in \e[200~…\e[201~,
  # disable (\e[?2004l) at teardown. Without it a paste reaches raxol's InputParser one char at a
  # time and every newline submits; with it the cockpit's paste buffer forwards the whole block.
  @paste_enable "\e[?2004h"
  @paste_disable "\e[?2004l"

  # Button-motion mouse tracking (\e[?1002h): report mouse MOTION while a button is held, not just
  # press/release. The raxol Driver enables only 1000 (button) + 1006 (SGR); without 1002 ghostty
  # sends nothing during a drag, so a Tlön text selection only highlights on mouseup. Enabled here
  # (additive to the Driver's modes, written after it starts); teardown's reset already clears 1002.
  @mouse_motion_enable "\e[?1002h"

  @doc "Start the cockpit and block until the operator quits — the entry point `mix aleph.run` calls."
  @spec run() :: :ok
  def run, do: run(0)

  # `strikes` = consecutive rapid crashes so far. The cockpit is an unlinked, monitored GenServer —
  # its crash surfaces here as a clean DOWN (a linked exit would kill this task before it restored
  # the terminal). funes (Repo/Bus) and the session terminals are supervised and keep running, so a
  # crash relaunches a FRESH cockpit in place — a reconnect, not a cold boot — unless it's looping.
  defp run(strikes) do
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        started = System.monotonic_time(:millisecond)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            restore_host_tty()
            # Capture a crashed exit — the alt-screen otherwise swallows it silently. (No-op on a
            # clean quit, so a normal `q` never spams the log.)
            log_crash(reason)
            act_on(resurrect_decision(reason, strikes, System.monotonic_time(:millisecond) - started))
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

  @doc false
  # The recovery decision after a cockpit goes DOWN. Pure so it's unit-tested without a TTY:
  #   :quit              — a clean operator quit (:normal / :shutdown), end the session.
  #   {:resurrect, n}    — a crash; relaunch, now on strike n.
  #   {:stop, n}         — the nth crash in a row hit the ceiling; stay down.
  # `crash_report/1` is the clean-vs-crash oracle (nil = normal/shutdown). A run that lasted at
  # least @resurrect_healthy_ms resets the strike count, so an isolated crash always heals.
  def resurrect_decision(reason, prev_strikes, alive_ms) do
    if is_nil(crash_report(reason)) do
      :quit
    else
      strikes = if alive_ms >= @resurrect_healthy_ms, do: 1, else: prev_strikes + 1
      if strikes >= @resurrect_max_fails, do: {:stop, strikes}, else: {:resurrect, strikes}
    end
  end

  defp act_on(:quit), do: :ok

  defp act_on({:stop, n}) do
    IO.puts(:stderr, "aleph crashed #{n}× in a row — staying down. Trace: #{Aleph.CrashLog.path()}")
    :ok
  end

  defp act_on({:resurrect, n}) do
    IO.puts(:stderr, "aleph crashed — recovering in place… (#{n}/#{@resurrect_max_fails})")
    run(n)
  end

  @impl true
  def init(_opts) do
    # Subscribe before the first read so nothing posted mid-boot is missed.
    Bus.subscribe_sessions()
    Bus.subscribe_threads()
    Bus.subscribe_messages()
    Bus.subscribe_habits()

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
        # Enable bracketed paste (\e[?2004h) so ghostty wraps a paste in \e[200~…\e[201~ and the
        # cockpit's paste buffer can forward it as one block instead of per-keystroke decoding.
        IO.write(@paste_enable)
        # Enable button-motion tracking (\e[?1002h) so a drag streams motion, not just press/release
        # — the Tlön selection highlights live instead of only on mouseup. See @mouse_motion_enable.
        IO.write(@mouse_motion_enable)

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
            paste_buffer: nil,
            input: nil,
            flash: nil,
            scrolls: %{},
            placements: [],
            render_scheduled?: false,
            stack: nil,
            health: nil,
            probed_at: 0,
            machine_retry_at: nil
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

  def handle_cast({:dispatch, %Event{type: :paste, data: %{phase: :start}}}, state) do
    # A paste began: start collecting. A fresh buffer even if one was somehow already open.
    {:noreply, %{state | paste_buffer: Aleph.PasteBuffer.start()}}
  end

  def handle_cast({:dispatch, %Event{type: :paste, data: %{phase: :end}}}, state) do
    # A paste ended: forward the whole buffer to the center terminal wrapped back in the markers
    # (tmux passes bracketed paste through; pi honors it as one multi-line paste). No center
    # terminal (a non-terminal space) → the paste is dropped, never leaked as stray keys.
    buffer = state.paste_buffer
    state = %{state | paste_buffer: nil}

    if buffer != nil do
      with term when is_pid(term) <- center_terminal(state) do
        Terminal.feed(term, Aleph.PasteBuffer.finish(buffer))
      end
    end

    {:noreply, state}
  end

  # While a paste is open, content keys accumulate into the buffer (a newline stays \n, NOT
  # :enter) instead of dispatching to the keymap — so a paste never submits mid-block. Must
  # precede the normal :key clause. Escape force-closes a stuck paste buffer (lost \e[201~) and
  # resumes normal key dispatch, so a dropped paste-end can't wedge the cockpit.
  def handle_cast({:dispatch, %Event{type: :key, data: %{key: :escape}}}, %{paste_buffer: buffer} = state)
      when not is_nil(buffer) do
    {:noreply, %{state | paste_buffer: nil}}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{paste_buffer: buffer} = state) when not is_nil(buffer) do
    {:noreply, %{state | paste_buffer: Aleph.PasteBuffer.accumulate(buffer, key)}}
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
  # Non-selectable panels (Dossier/Stack/Health, the center terminal) return nil → no-op.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left, action: :press}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}
    dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, state)
  end

  # A left drag/release over the terminal body: forwarded to the PTY so tmux does the selecting (and
  # copies on release). Routed per-event by position — no drag state — so a motion that leaves the
  # terminal simply stops forwarding. Anywhere else, a drag/release is not a gesture aleph acts on.
  # `:move` is the atom raxol's InputParser emits for a button-motion SGR report; `:motion` is
  # accepted too so a raxol rename can't silently kill the live-drag forwarding.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left, action: action}}}, state)
      when action in [:move, :motion, :release] do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}
    forward_terminal_mouse(Mouse.hit_panel(state.placements, x, y), action, x, y, state)
    {:noreply, state}
  end

  # Any other mouse event (right/middle button, motion with no button) is not handled.
  def handle_cast({:dispatch, %Event{type: :mouse}}, state), do: {:noreply, state}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # A posted message may @-mention a Tlön coworker — wake it by injecting the message as a turn
  # into its tmux window. Routed before the general repaint clause. Best-effort: a window that
  # isn't up yet is skipped (the coworker is never spawned just to deliver a mention).
  @impl true
  def handle_info({:message_posted, row}, state) do
    desktop_notify(:message_posted, row)
    mention_notify(row)
    {:noreply, render(state)}
  end

  def handle_info({tag, row}, state)
      when tag in [
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

  # Habit review events refresh the Habits panel (Tlön). No desktop notification — a proposed
  # habit is a quiet queue entry for review, not an interrupt.
  def handle_info({tag, _row}, state) when tag in [:habit_proposed, :habit_approved, :habit_rejected] do
    {:noreply, render(state)}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    # A pending coalesced :render is now redundant (this tick paints); drop the flag so it no-ops.
    state = %{state | render_scheduled?: false}
    # Expire the cached Tlön probes on the probe cadence — render refills them lazily (and only
    # when Tlön is the active space), so the subprocess battery runs at @probe_ms, never per frame.
    state = maybe_expire_probes(state)
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

  # @-mention delivery: a posted message naming a Tlön coworker (`@pi-machine` / `@claude-machine`)
  # is injected as a turn into that coworker's tmux window, so a cold pane gets woken instead of
  # silently accumulating an unread thread. Pure routing lives in Aleph.Mention; this is the edge —
  # best-effort tmux send-keys, never a crash on a missing window.
  defp mention_notify(row) do
    lead = thread_lead(row)

    for {window, text} <- Aleph.Mention.route(row, lead: lead),
        index = tlon_window_index(window),
        not is_nil(index) do
      inject_turn(index, text)
    end

    :ok
  end

  # The funes handle of the coworker staffed on this message's thread (its lead), or nil.
  # Read in-process (aleph boots funes); never crash the hub if the lookup fails.
  defp thread_lead(%{thread_id: tid}) when not is_nil(tid) do
    Funes.thread_lead(tid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp thread_lead(_), do: nil

  # The tmux window index for a named coworker window, from the live session (nil if not up).
  defp tlon_window_index(name) do
    Enum.find_value(tlon_tabs(), fn %{name: n, index: index} -> if n == name, do: index end)
  end

  # Inject `text` as a submitted turn into window `index`: literal text, then the Enter key — so a
  # multiline body flattened to one line reaches the coworker's input as a single message.
  defp inject_turn(index, text) do
    target = "#{@tlon_session}:#{index}"
    _ = System.cmd("tmux", tlon_tmux(["send-keys", "-l", "-t", target, text]), stderr_to_stdout: true)
    _ = System.cmd("tmux", tlon_tmux(["send-keys", "-t", target, "Enter"]), stderr_to_stdout: true)
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

  # Clicking the center terminal. In the Tlön workspace, row 0 is aleph's OWN tab strip — a click
  # there selects that tmux window (never forwarded to the PTY). Below it is the terminal proper:
  # forwarded to the PTY when the embedded program tracks the mouse (tmux `mouse on` selects; a TUI
  # hit-tests its own regions), shifted UP by the tab row so the cell under the cursor is the one hit.
  defp dispatch_click({Panel.Terminal, data, rect}, x, y, state) do
    tabs = tabs_of(data)
    local_y = y - rect.y

    if tabs != [] and local_y == 0 do
      select_tlon_window(Panel.Terminal.tab_at_x(tabs, x - rect.x))
      {:noreply, render(state)}
    else
      offset = if tabs == [], do: 0, else: 1

      with term when is_pid(term) <- center_terminal(state) do
        Terminal.mouse(term, :press, clamp_cell(x - rect.x, rect.w), clamp_cell(local_y - offset, rect.h))
      end

      {:noreply, state}
    end
  end

  defp dispatch_click({panel, data, rect}, _x, y, state), do: apply_pick(Panel.pick(panel, data, rect, y - rect.y), state)

  defp tabs_of(data) when is_map(data), do: data[:tabs] || []
  defp tabs_of(_data), do: []

  # Select a Tlön tmux window by the clicked tab's index; nil (a click past the tabs) is a no-op.
  defp select_tlon_window(%{index: idx}) do
    System.cmd("tmux", tlon_tmux(["select-window", "-t", "#{@tlon_session}:#{idx}"]), stderr_to_stdout: true)
    :ok
  end

  defp select_tlon_window(_tab), do: :ok

  # A drag/release over the terminal body (below the tab strip) → the PTY, shifted up by the tab row;
  # anywhere else is ignored. Mirrors dispatch_click's body branch so a click and a drag agree on
  # where the terminal starts.
  defp forward_terminal_mouse({Panel.Terminal, data, rect}, action, x, y, state) do
    offset = if tabs_of(data) == [], do: 0, else: 1
    local_y = y - rect.y

    if local_y >= offset do
      with term when is_pid(term) <- center_terminal(state) do
        Terminal.mouse(term, action, clamp_cell(x - rect.x, rect.w), clamp_cell(local_y - offset, rect.h))
      end
    end

    :ok
  end

  defp forward_terminal_mouse(_hit, _action, _x, _y, _state), do: :ok

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

  # The `m` verb landed: advance the coworker's driver model one step round the ring and persist
  # it (Aleph.Config). Honest about scope: the RUNNING coworker keeps its model — the override
  # applies wherever Profiles.fetch flows on the next spawn (aleph:reset, or kill the pi window).
  defp apply_effect({:cycle_coworker_model, profile_name}, state) do
    current = Profiles.fetch(profile_name)
    next = Profiles.next_model(current && current.model)
    Aleph.Config.put_coworker_model(profile_name, next)

    {:noreply,
     render(%{state | flash: "coworker driver → #{next.provider}/#{next.model} — applies on next spawn (aleph:reset)"})}
  rescue
    e -> {:noreply, render(%{state | flash: "settings write failed: #{Exception.message(e)}"})}
  end

  # `enter_or_spawn`: if the focused thread already has a live session, it's already the center —
  # nothing to do (you're already working there). Otherwise spawn one onto it. The replacement for
  # the old bare `s` verb — one `spawn_onto/2` path, reached via `n` (new thread) or `Enter` (existing).
  defp enter_or_spawn(thread_id, state) do
    case safe_terminal(thread_id) do
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
        case safe_spawn_harness(thread_id, exports, cols: cols, rows: rows) do
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
  # to_atom, NOT to_existing_atom: the char set is bounded (a-z, A-Z, 0-9 → 36 known atoms), so there's
  # no atom-table-exhaustion risk — and to_existing_atom CRASHES the cockpit on any letter whose atom
  # wasn't already interned (e.g. pressing "o" when :o exists nowhere as a literal). The ghostty_key
  # unit tests masked this: their :x/:c/:v literals intern exactly those atoms at compile time.
  defp char_key(<<cp>>) when cp in ?a..?z, do: String.to_atom(<<cp>>)
  defp char_key(<<cp>>) when cp in ?A..?Z, do: String.to_atom(<<cp + 32>>)
  defp char_key(<<cp>>) when cp in ?0..?9, do: String.to_atom("digit_#{<<cp>>}")
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
    # Fill the probe cache (Tlön only) and find-or-spawn the machine coworker — both stateful,
    # both rate-limited, both OUT of the per-frame hot path.
    state =
      state
      |> ensure_probes()
      |> ensure_machine_coworker()
      |> ensure_claude_coworker()
      |> ensure_third_coworker()
      |> ensure_log_window()

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
      stack: state.stack || @empty_stack,
      health: state.health,
      logbook: logbook_read(state.active_key),
      triage: if(state.active_key == :orbis, do: triage_read(threads)),
      habits: habits_read(state.active_key),
      settings: settings_read(state.active_key),
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

  # The Tlön center's read: the embedded tmux client. Lookup only — the find-or-spawn lives in
  # ensure_machine_coworker (render's stateful preamble), so a failing spawn can back off
  # instead of re-materialising the profile and re-issuing tmux new-session every frame.
  defp machine_read(%{active_key: :tlon}) do
    case render_state_of(safe_terminal(:machine)) do
      %{} = render_state -> Map.put(render_state, :tabs, tlon_tabs())
      other -> other
    end
  end

  defp machine_read(_state), do: :no_session

  defp render_state_of(nil), do: :no_session
  defp render_state_of(term), do: Terminal.render_state(term)

  # Sessions is supervised (Aleph.Supervisor) but the cockpit is NOT — a `Sessions.terminal/1`
  # against a torn-down registry raises `(EXIT) no process`, which used to propagate up through
  # render and kill the cockpit, wedging all input (Enter went nowhere). Degrade to nil so a dead
  # registry just reads as "no session"; the supervisor restarts it on its own.
  defp safe_terminal(thread_id) do
    Sessions.terminal(thread_id)
  catch
    :exit, _ -> nil
  end

  defp safe_spawn_harness(thread_id, exports, opts) do
    Sessions.spawn_harness(thread_id, exports, opts)
  catch
    :exit, _ -> {:error, :sessions_down}
  end

  # The terminal that owns the keys, by space: Sessions → the focused thread's session; Tlön →
  # the embedded tmux client. nil elsewhere.
  defp center_terminal(%{active_key: :sessions} = state), do: state |> focused() |> terminal_for()
  defp center_terminal(%{active_key: :tlon}), do: safe_terminal(:machine)
  defp center_terminal(_state), do: nil

  # The thread `c` composes onto, derived per keypress (like center_live?): the focused project
  # thread in Orbis/Sessions; in Tlön the MACHINE thread — the operator working the box posts to
  # the machine coworker, never a stale project thread id carried over from Orbis. nil (no thread)
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
  defp terminal_for(%{id: id}), do: safe_terminal(id)

  # Expire cached probes once @probe_ms has passed; render's ensure_probes refills lazily.
  defp maybe_expire_probes(state) do
    if System.monotonic_time(:millisecond) - state.probed_at >= @probe_ms do
      %{state | stack: nil, health: nil}
    else
      state
    end
  end

  # Fill the probe cache when Tlön is active and the cache is cold. Elsewhere the probes stay
  # nil — git/nix/df/tmux forks are wasted on spaces that never show them.
  defp ensure_probes(%{active_key: :tlon, stack: nil} = state) do
    %{state | stack: stack_read(), health: health_read(), probed_at: System.monotonic_time(:millisecond)}
  end

  defp ensure_probes(state), do: state

  # The STACK read: branch, dirty status, ahead/behind, status summary, enriched commits.
  # One ahead_behind call, destructured — it forks a git per call.
  defp stack_read do
    {ahead, behind} = Aleph.Stack.ahead_behind()

    %{
      branch: Aleph.Stack.branch(),
      dirty: Aleph.Stack.dirty?(),
      ahead: ahead,
      behind: behind,
      status_summary: Aleph.Stack.status_summary(),
      commits: Aleph.Stack.commits(),
      files: Aleph.Stack.recent_files(),
      tools: Aleph.Stack.tools()
    }
  end

  # The HEALTH read. One nix_status call for gen+behind — nix-env --list-generations is the
  # single most expensive probe in the battery; calling it once matters.
  defp health_read do
    {nix_gen, nix_behind} = Aleph.Stack.nix_status()

    %{
      funes_up: Aleph.Stack.funes_up?(),
      tlon_up: Aleph.Stack.tlon_up?(),
      nix_gen: nix_gen,
      nix_behind: nix_behind,
      disk_pct: Aleph.Stack.disk_pct(),
      mem_pct: Aleph.Stack.mem_pct(),
      load_avg: Aleph.Stack.load_avg(),
      tools: Aleph.Stack.tools()
    }
  end

  # HABITS reads are only gathered on Tlön — the machine-wide review queue (pending) and the
  # always-loaded set (approved). Machine-wide, so not keyed on a focused thread.
  defp habits_read(:tlon), do: %{pending: Dossier.pending_habits(), approved: Dossier.approved_habits()}
  defp habits_read(_key), do: nil

  # SETTINGS reads: the active space's coworker driver (override merged by Profiles.fetch) + the
  # ring the `m` verb cycles. Any space with a coworker gets the panel's data; spaces without one
  # get nil (the panel renders nothing).
  defp settings_read(key) do
    with profile_name when is_binary(profile_name) <- Space.fetch(key).coworker,
         %Profile{} = p <- Profiles.fetch(profile_name) do
      %{
        profile: profile_name,
        model: p.model,
        ring: Profiles.model_ring(),
        override?: Aleph.Config.coworker_model(profile_name) != nil
      }
    else
      _ -> nil
    end
  end

  # LOGBOOK reads are only gathered on Tlön — the machine thread's issues + recent messages,
  # the shared notebook for notes and observations about the env.
  defp logbook_read(:tlon) do
    case Channel.machine_thread() do
      nil ->
        nil

      thread ->
        %{
          thread: thread,
          issues: Dossier.open_issues_for_thread(thread).shown,
          messages: Channel.recent_messages(thread, 10)
        }
    end
  end

  defp logbook_read(_key), do: nil

  # TRIAGE reads: cross-thread blockers, failed checks, and unassigned threads.
  # Gathers from all open threads — a funes Board aggregate.
  # Each section is `%{shown: [...], more: count}` so the panel can render "+N more".
  defp triage_read(threads) do
    scopes = for thread <- threads, do: {thread, Funes.Board.in_scope(thread)}

    all_blockers =
      Enum.flat_map(scopes, fn {thread, scope} ->
        Enum.map(scope.blockers.shown, fn b -> %{thread_title: thread.title, summary: b.summary} end)
      end)

    all_failed_checks =
      Enum.flat_map(scopes, fn {thread, scope} ->
        scope.checks.shown
        |> Enum.filter(fn c -> c.kind == "check_failed" end)
        |> Enum.map(fn c -> %{thread_title: thread.title, cmd: cmd_from_detail(c.detail)} end)
      end)

    unassigned =
      threads
      |> Enum.filter(fn thread -> is_nil(thread.agent_id) end)
      |> Enum.map(fn thread -> %{title: thread.title} end)
      |> Enum.take(5)

    %{
      blockers: cap(all_blockers, 5),
      failed_checks: cap(all_failed_checks, 5),
      unassigned: unassigned
    }
  end

  defp cap(list, n), do: %{shown: Enum.take(list, n), more: max(length(list) - n, 0)}

  defp cmd_from_detail(%{"cmd" => cmd}), do: cmd
  defp cmd_from_detail(_), do: "check"

  # The Tlön machine coworker: a pi session working ON the box on a persistent "machine" thread
  # (so its work is triageable). pi by design — Tlön is meta/machine work, claude stays the
  # deliberate escalation (AGENTS.md routing). Find-or-spawned here (render's stateful preamble),
  # with a backoff: a failed spawn used to retry the whole materialise+tmux pipeline on EVERY
  # render — a spawn storm whenever the coworker couldn't start.
  defp ensure_machine_coworker(%{active_key: :tlon} = state) do
    now = System.monotonic_time(:millisecond)

    cond do
      is_pid(safe_terminal(:machine)) -> state
      not machine_spawn_due?(state.machine_retry_at, now) -> state
      is_pid(spawn_machine_coworker()) -> state
      true -> %{state | machine_retry_at: now + @machine_spawn_backoff_ms}
    end
  end

  defp ensure_machine_coworker(state), do: state

  # The Tlön Claude-Code window: real `claude`, honestly identified (no pi-multi-account
  # impersonation — see Aleph.Profiles' @profiles comment for why that path is avoided by default).
  # A second tmux window in the SAME session as the pi coworker, joined to the SAME machine thread,
  # so the two coordinate over funes messages like any two agents. Gated on the pi window already
  # existing (its spawn opens/finds the machine thread this one joins) and on the window not already
  # being there (tmux `new-window` isn't idempotent like `new-session -A` — a naive re-run on every
  # render would spawn a fresh claude every tick).
  defp ensure_claude_coworker(%{active_key: :tlon} = state) do
    cond do
      not is_pid(safe_terminal(:machine)) ->
        state

      Enum.any?(tlon_tabs(), &(&1.name == "claude")) ->
        state

      true ->
        spawn_claude_window()
        state
    end
  end

  defp ensure_claude_coworker(state), do: state

  # An optional THIRD coworker for experiments (`$TLON_THIRD_AGENT="handle:window"`, off by default):
  # a second Claude-Code window on its own funes identity, to break the two-body agree/disagree
  # dynamic. Same gating as the claude window (pi up, its own window absent); `Aleph.Mention` picks
  # up the same env so the third joins the wake-loop.
  defp ensure_third_coworker(%{active_key: :tlon} = state) do
    case Aleph.Mention.third_agent() do
      %{author: author, window: window} ->
        cond do
          not is_pid(safe_terminal(:machine)) ->
            state

          Enum.any?(tlon_tabs(), &(&1.name == window)) ->
            state

          true ->
            spawn_agent_window(author, window)
            state
        end

      nil ->
        state
    end
  end

  defp ensure_third_coworker(state), do: state

  # The `chat` tab (the third Tlön window): the INTERACTIVE machine-chat — machine-scope threads as
  # foldable blocks with author-turn grouping (fold/zoom/scroll), so the pi/claude tabs can stay
  # their raw harness selves. NOT a coworker — no funes identity, no wake-loop entry (Aleph.Mention
  # doesn't know it); it just polls the db the cockpit writes. Gated like the claude window: pi up
  # (so a machine thread exists to read), window absent (`new-window` isn't idempotent), retried each
  # render — a failed open just leaves the tab missing.
  defp ensure_log_window(%{active_key: :tlon} = state) do
    cond do
      not is_pid(safe_terminal(:machine)) -> state
      Enum.any?(tlon_tabs(), &(&1.name == "chat")) -> state
      true -> spawn_log_window() && state
    end
  end

  defp ensure_log_window(state), do: state

  # Open the `chat` window running `mix aleph.machine_chat` from the aleph project (where mise/mix
  # resolve). It inherits the tlon session's `FUNES_DB`, so it reads the SAME db the cockpit writes —
  # the whole point of the poll-the-db design (a separate process can't share the in-node Bus).
  # Fire-and-forget: a failed spawn leaves the tab absent and the next render retries.
  defp spawn_log_window do
    dir = Path.join(Profiles.repo(), "modules/aleph")
    script = "export TERM=xterm-256color\ncd #{dir}\nexec mise exec -- mix aleph.machine_chat"
    System.cmd("tmux", tlon_tmux(["new-window", "-t", @tlon_session, "-n", "chat", script]), stderr_to_stdout: true)
    # chat is the primary Tlön surface, so seat it as tab 1: move it below base-index, then renumber
    # so it becomes the first window and pi/claude shift to 2/3.
    System.cmd("tmux", tlon_tmux(["move-window", "-s", "#{@tlon_session}:chat", "-t", "#{@tlon_session}:0"]),
      stderr_to_stdout: true
    )

    System.cmd("tmux", tlon_tmux(["move-window", "-r", "-t", "#{@tlon_session}:0"]), stderr_to_stdout: true)
  end

  # `tmux new-window`, not Sessions.spawn_harness: this rides as window 1 of the ALREADY-embedded
  # tlon tmux session (the pi coworker's window 0), not a separate Aleph.Terminal/PTY of its own.
  # Fire-and-forget: a failed spawn (funes down, no thread yet) just leaves the window absent, and
  # `ensure_claude_coworker` retries it on the next render — no backoff needed, `new-window` is cheap
  # and idempotent-by-absence-check above.
  defp spawn_claude_window, do: spawn_agent_window(@claude_agent, "claude")

  # Open a Claude-Code window named `window` on the machine thread as funes `agent`. The claude and
  # the experiment third voice both ride this — same launcher, distinct identity + tab label.
  defp spawn_agent_window(agent, window) do
    with id when is_integer(id) <- machine_thread_id(),
         {:ok, %{exports: exports}} <- Spawn.join(id, agent, mandate: "machine") do
      script = "export TERM=xterm-256color\n" <> exports <> "\nexec " <> claude_launcher()
      System.cmd("tmux", tlon_tmux(["new-window", "-t", @tlon_session, "-n", window, script]), stderr_to_stdout: true)
    end
  end

  defp claude_launcher, do: Path.join(Profiles.repo(), "modules/manos/claude-code/launch.sh")

  @doc false
  # Is a machine-coworker spawn attempt due? `machine_retry_at` is nil until an attempt FAILS (the
  # "no backoff pending" sentinel — try now), then a future monotonic timestamp for @machine_spawn_backoff_ms.
  # It MUST be nil, not 0: BEAM monotonic time starts large-NEGATIVE, so `now < 0` reads as "still
  # backing off" forever and the coworker never spawns (regression — f861c84).
  def machine_spawn_due?(nil = _retry_at, _now), do: true
  def machine_spawn_due?(retry_at, now), do: now >= retry_at

  # Materialise the Tlön space's coworker profile, find-or-create the machine identity, then spawn
  # the Tlön center: an embedded tmux client attached to the standing session (pi as window 0 if
  # absent) — an aleph restart re-attaches to the running pi instead of spawning another.
  defp spawn_machine_coworker do
    space = Space.fetch(:tlon)

    with %Profile{} = profile <- Profiles.fetch(space.coworker),
         {:ok, _dir} <- materialise_profile(profile),
         {:ok, exports} <- machine_exports(@machine_agent),
         # kitty: false — tmux wants its Ctrl+B prefix as legacy \x02, not CSI-u (see Terminal.init).
         {:ok, pid} <- safe_spawn_harness(:machine, exports, launcher: profile_launcher(profile), kitty: false) do
      pid
    else
      _error -> nil
    end
  end

  # Wrap the raising materialiser so a filesystem hiccup degrades to "no coworker", never a cockpit crash.
  defp materialise_profile(profile) do
    {:ok, Profiles.materialise!(profile)}
  rescue
    e -> {:error, e}
  end

  @doc false
  # `new-session -A` = attach-or-create; pi becomes window 0's command on first creation only.
  #
  # The coworker's pi runs from its profile's config dir (`PI_CODING_AGENT_DIR`) — its own
  # settings/mcp/sandbox. The machine identity minted above (`machine_exports`) is exported into the
  # launch env, and Tlön's profile mcp.json binds funes to it on the MACHINE scope (Aleph.Profiles
  # @tlon_funes_mcp) — so the coworker's work lands on the machine thread the LOGBOOK renders, walled
  # off from project threads by the DB scope CHECK (self-contained by SCOPE, not by severance). A persona, if
  # the profile has one, rides as `--append-system-prompt <file>`. Both the config dir and the persona
  # flag travel into `MANOS_RELOAD_CMD` so a manos/reload respawn stays on-profile. (Paths are the
  # single-user machine's — no spaces/quotes — so they sit inside the launcher's quoting bare.)
  def profile_launcher(%Profile{} = profile) do
    base = Application.get_env(:aleph, :spawn_launcher, "mise exec -- pi")
    dir = Profiles.config_dir(profile.name)
    prompt = if profile.system_prompt, do: " --append-system-prompt #{Path.join(dir, "system_prompt.md")}", else: ""
    # The model MUST ride as a `--model` flag, not just settings.json `defaultModel`: pi resolves the
    # settings default BEFORE pi-multi-account registers the `anthropic` provider, so a `defaultModel`
    # of claude-* can't be found and pi silently falls back to the first models.json model (glm). The
    # CLI flag is applied AFTER extensions load, so it sticks. Empirically verified 2026-08-17.
    model =
      case profile.model do
        %{provider: prov, model: m, thinking: think} -> " --model #{prov}/#{m} --thinking #{think}"
        _ -> ""
      end

    pi = "env PI_CODING_AGENT_DIR=#{dir} #{base}#{prompt}#{model}"
    # MANOS_RELOAD_CMD: how manos/reload respawns pi in place — `--continue` resumes the most-recent
    # session (the one being killed), so a reload keeps the thread across the restart.
    reload_cmd = {"MANOS_RELOAD_CMD", pi <> " --continue"}
    env_flags = Enum.map_join([reload_cmd], " ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)
    # The coworker's PRIVATE tmux server: `-L aleph-<profile>` + the profile's persistence-free
    # tmux.conf (`-f` applies on server creation; an already-running server keeps its config, and
    # `aleph:reset` kills the server). That conf also owns the chrome-off options (status off,
    # blank status-format, pane-border-status off — aleph draws the Tlön header + tab strip itself)
    # and the readable copy-mode mode-style, so the launcher stays one plain `new-session`.
    # Window 0 is named `pi` so the tab strip has a clean label.
    "tmux -L #{Profiles.socket(profile.name)} -f #{Path.join(dir, "tmux.conf")}" <>
      " new-session -A -s #{@tlon_session} -n pi #{funes_identity_flags()} #{env_flags} '#{pi}'"
  end

  @doc false
  # `-e FUNES_X="$FUNES_X"` for each identity var. The Tlön pi's MCP wiring reads `${FUNES_MCP_URL}`
  # (profile mcp.json) and mints a bearer for FUNES_THREAD/FUNES_AUTHOR — but spawn_harness only
  # `export`s those in pi's ONE-SHOT launch shell, so they live in pi's PROCESS env alone. A
  # continuum/`--continue` restore, a `respawn-pane`, or a reload in a clean shell then boots with
  # `${FUNES_MCP_URL}` empty → the funes server never registers ("Tool not found", never the 404 the
  # adapter self-heals). Putting them in the tmux SESSION env via `-e` makes the identity durable
  # across respawns; `-e` also refreshes on `new-session -A`, so an aleph restart re-freshes a stale
  # identity instead of stranding it (the wired-wrong case aleph:reset used to be needed for). bash
  # sourced the exports first, so it expands the values here into the current literal ones.
  def funes_identity_flags do
    Enum.map_join(@funes_identity_env, " ", fn var -> ~s(-e #{var}="$#{var}") end)
  end

  # POSIX single-quote: escape embedded quotes as '\'' so the value survives the shell verbatim.
  defp sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # The Tlön workspace's windows as tabs — aleph draws them itself (tmux's own status bar is off),
  # so it asks tmux for the live truth rather than tracking cockpit state (can't drift). Best-effort:
  # the session not being up yet is an empty strip, not a crash.
  defp tlon_tabs do
    case System.cmd(
           "tmux",
           tlon_tmux(["list-windows", "-t", @tlon_session, "-F", "\#{window_active}\t\#{window_index}\t\#{window_name}"]),
           stderr_to_stdout: true
         ) do
      {out, 0} -> parse_tlon_tabs(out)
      _ -> []
    end
  end

  # Every tmux call about the Tlön coworker targets its private server (`-L aleph-<profile>`),
  # never the user's default one.
  defp tlon_tmux(args), do: ["-L", Profiles.socket(Space.fetch(:tlon).coworker)] ++ args

  @doc false
  # `window_active` is "1" for the current window, "0" otherwise; each line is
  # `<active>\t<index>\t<name>` — the index is tmux's window index, for select-window on a tab click.
  def parse_tlon_tabs(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 3) do
        [active, index, name] -> [%{name: name, active?: active == "1", index: index}]
        _ -> []
      end
    end)
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

  # Keep the center session's PTY sized to the center region so it reflows with the window. Sized to
  # the EXACT center Terminal rect (Aleph.View.center_rect — the one layout authority), so the PTY
  # matches what's on screen; the terminal reflows on every window resize.
  defp resize_focused_terminal(state) do
    with term when is_pid(term) <- center_terminal(state) do
      {cols, rows} = center_dims(state)
      Terminal.resize(term, cols, rows)
    end
  end

  # Size the PTY to EXACTLY the center Terminal's content rect (Aleph.View.center_rect), so pi never
  # draws past the frame (a wider PTY spills; a shorter one leaves a dead band). Tlön reserves the
  # terminal's top row for aleph's own tab strip, so its PTY is one row shorter than the rect.
  defp center_dims(%{active_key: active_key, w: w, h: h}) do
    rect = View.center_rect(w, h)
    {max(rect.w, 1), max(rect.h - tab_reserve(active_key), 1)}
  end

  defp tab_reserve(:tlon), do: 1
  defp tab_reserve(_), do: 0

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
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable)

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
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable <> "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h")
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
         false <- crash_issue_open?(Dossier.open_issues_for_thread(thread), summary) do
      Dossier.raise_issue(%{thread_id: id, summary: summary, evidence: report, found_by: "aleph"})
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @doc false
  # Dedupe against the thread's open issues. open_issues_for_thread returns the capped
  # `%{shown, more}` shape, NOT a bare list — enumerating the map raised here, the rescue above
  # swallowed it, and a crashed cockpit silently never filed its issue. Public + tested so the
  # shape contract can't silently regress again.
  @spec crash_issue_open?(%{shown: [map()]}, String.t()) :: boolean()
  def crash_issue_open?(%{shown: shown}, summary), do: Enum.any?(shown, &(&1.summary == summary))
end
