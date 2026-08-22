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
  alias Aleph.Panel.WindowBar
  alias Aleph.Profile
  alias Aleph.Profiles
  alias Aleph.Sessions
  alias Aleph.Space
  alias Aleph.Terminal
  alias Aleph.Tlon.Focus
  alias Aleph.Tlon.Settings
  alias Aleph.View
  alias Funes.Bus
  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.MCP.Spawn
  alias Funes.Staff
  alias Ghostty.KeyEvent
  alias Raxol.Core.Events.Event

  # `Space.world?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

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

  # The World's cast is roster-driven (`ensure_world_roster/1`, C2.3): head = the center (embedded
  # terminal, `new-session`), tail = tmux windows (`new-window`), harness-dispatched. Funes handle =
  # `"<name>-machine"`, tmux window = `"<name>"` (`roster_entry/1`). No more hardcoded
  # tertius/hronir/claude-machine identity — the seed roster (surveyor "tertius", builder "hronir")
  # reproduces the old Borges cast (**uqbar** console · **hronir** builder · **tertius**
  # orchestrator) as DATA, not constants.

  # tmux is a first-class stack citizen here: each World's center is a real `tmux attach`, so the
  # workspace gets mouse, windows, and copy-mode, and it SURVIVES aleph restarts. Session/socket are
  # id-derived (world_session/1, world_socket/1, near tlon_tmux/2) — not name-derived — so a world
  # rename can't orphan the running session and two worlds never collide.

  # Tlön probe cadence: the Stack/Health reads fork subprocesses (git ×~6, nix-env, df, tmux)
  # and open a TCP probe — far too heavy to run per render (a streaming terminal coalesces to
  # ~125 renders/sec, and one nix-env alone exceeds the whole 8ms window; renders serialized
  # and starved input). Probes are CACHED in cockpit state and refreshed at most this often,
  # on the tick; every other render (keys, Bus events, terminal frames) reads the cache.
  @probe_ms 2_000

  # A failed machine-coworker spawn must not retry on every render (materialise + tmux
  # new-session per frame = a spawn storm whenever the coworker can't start). Back off.
  @machine_spawn_backoff_ms 5_000

  # Same backoff, per-thread: a staffed machine thread whose `tmux new-window`/`Spawn.join`
  # keeps failing (funes hiccup, a stale agent) must not retry on every render either — see
  # `ensure_thread_sessions`.
  @thread_spawn_backoff_ms 5_000

  # How long to let a freshly-spawned per-thread window settle between typing its opening turn and
  # sending Enter (the two-phase inject). A just-booted Claude Code TUI takes the text but
  # swallows an Enter that arrives in the same burst; a beat later it submits cleanly. Tunable —
  # bump it if the first turn still lands typed-but-unsent.
  @opening_submit_delay_ms 1_200

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
    # The global activity topic is a strict superset of messages_topic for `:message_posted`
    # (Bus.broadcast always publishes a message to both) — subscribing to messages_topic too
    # would double-deliver every message. Riding activity alone also brings fact_banked /
    # event_recorded / issue_raised / question_raised in globally (the Activity feed's buffer),
    # not just for the focused thread.
    Bus.subscribe_activity()
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
            # Tlön's lazygit focus (which sidebar column/pane/section, and whether we're in the
            # center tmux terminal). Persistent across keypresses — the keymap reads+advances it,
            # only in the Tlön space. Defaults in-terminal, so Tlön opens with keys going to tmux.
            focus: Focus.new(),
            # The World tmux window the center is previewing (Worlds Slice 0, tweak #1): a hover over
            # a window-bearing pane (Leaves) re-points the center here WITHOUT taking focus; a commit
            # (`commit_preview/1`) drops keys into it. nil = center on its default (active) window.
            previewed_window: nil,
            # Which World window is attached in the center (C3.3): `{:leaf, id}` when a leaf's own
            # `t<id>` window is attached, else `{:leader, name | nil}`. Leaves washes the leaf row
            # whose id matches. Set by attach_leaf/2 and the WindowBar tab click.
            focused_session: {:leader, nil},
            # C3.4: `[`/`]` cycle this index into the active World's right column, so only one of
            # Health/Activity/Leaves shows (full-height) at a time. Index 0 = the first right panel
            # (Health) — the default; the operator tunes it live.
            right_pane_view: 0,
            paste_buffer: nil,
            input: nil,
            # The Tlön settings modal (nil = closed). Persistent like `input`: the keymap opens it
            # (`,`), navigates it, and the modal owns every key until dismissed.
            modal: nil,
            flash: nil,
            scrolls: %{},
            placements: [],
            render_scheduled?: false,
            stack: nil,
            health: nil,
            # The Memory pane's read (coverage + floor + pending habits), cached with stack/health;
            # invalidated on a habit approve/reject so the pane reflects the write immediately.
            memory: nil,
            # The Leaves rollup (machine_overview), cached with the other probes so its item count is
            # available to the keymap for j/k clamping at keypress time (before reads exist).
            leaves: nil,
            # The funes activity feed's bounded buffer (Tlön right sidebar + the footer pulse):
            # `{tag, row}` Bus events, newest-first, capped at 50 by `push_activity/3`.
            activity: [],
            # Recently-seen `{tag, id}` keys (capped ~100) — the first-sight gate. A tagged event on
            # the FOCUSED thread arrives TWICE (its thread topic + the global activity topic), so this
            # dedupes side effects (notify/nudge/append) to exactly once. See `fresh?/3`.
            seen_events: [],
            probed_at: 0,
            machine_retry_at: nil,
            # The standing center coworker's own machine thread — captured once, at its
            # first successful spawn (`ensure_center`), so `ensure_thread_sessions` can
            # tell it apart from an ordinary staffed machine thread it should spawn a session for.
            standing_thread_id: nil,
            # Per-thread spawn backoff (mirrors `machine_retry_at`) — thread_id => monotonic
            # retry-at, so a thread whose session keeps failing to spawn isn't retried every render.
            thread_spawn_retry: %{},
            # The two-phase opening-turn inject (see `ensure_thread_sessions`). `opening_text_at`:
            # thread_id => monotonic ms when the turn's TEXT was typed into the fresh `t<id>`
            # window; the Enter follows @opening_submit_delay_ms later so a booting TUI doesn't
            # swallow it. `opening_injected`: thread ids already SUBMITTED (done, never re-touched).
            opening_text_at: %{},
            opening_injected: MapSet.new()
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
    # `focus` rides in `state` (persistent); `tlon_layout` is derived per keypress, like the two
    # above, and dropped on the way back — the keymap reads it to navigate, the cockpit never stores it.
    keymap_state =
      %{state | flash: nil}
      |> Map.put(:center_live?, center_terminal(state) != nil)
      |> Map.put(:composer_thread_id, composer_thread_id(state))
      |> Map.put(:tlon_layout, tlon_layout(state))

    {next, effect} = Keymap.handle(key, keymap_state)
    next = reset_scrolls(state, Map.drop(next, [:center_live?, :composer_thread_id, :tlon_layout]))
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
    mention_notify(row, state)
    {:noreply, render(push_activity(state, :message_posted, row))}
  end

  # The activity-buffer subset of this clause's tags: `Funes.Bus` publishes these to the global
  # activity topic (see funes/lib/funes/bus.ex), not just the focused thread's topic — so this
  # is where the Activity feed's `state.activity` gets filled. thread_opened/closed/assigned and
  # session_started/ended ride ONLY their own topics (never activity), so they never reach here
  # via a second path and are left out of the buffer.
  # First-sight gate: a tagged event on the FOCUSED thread is delivered twice (thread topic +
  # activity topic). Dropping the repeat here means desktop_notify/nudge/append each fire once.
  @activity_tags [
    :fact_banked,
    :event_recorded,
    :issue_raised,
    :issue_resolved,
    :question_raised,
    :question_resolved,
    :todo_added,
    :todo_completed
  ]

  def handle_info({tag, row}, state)
      when tag in [
             :fact_banked,
             :event_recorded,
             :issue_raised,
             :issue_resolved,
             :question_raised,
             :question_resolved,
             :todo_added,
             :todo_completed,
             :thread_opened,
             :thread_closed,
             :thread_assigned,
             :session_started,
             :session_ended
           ] do
    if fresh?(state, tag, row) do
      state = %{state | seen_events: cap_seen([seen_key(tag, row) | state.seen_events])}
      desktop_notify(tag, row)
      nudge_tertius_on_finish(tag, row, state)
      state = if tag in @activity_tags, do: push_activity(state, tag, row), else: state
      {:noreply, render(state)}
    else
      {:noreply, state}
    end
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

  @activity_cap 50
  @seen_cap 100

  # Prepend `{tag, row}` to the activity buffer (newest-first, capped at @activity_cap). Tagged
  # events are already deduped by the `fresh?/3` first-sight gate in handle_info; messages reach
  # the cockpit once (only via the activity topic, since init dropped subscribe_messages).
  defp push_activity(state, tag, row) do
    %{state | activity: Enum.take([{tag, row} | state.activity], @activity_cap)}
  end

  # First-sight test for a tagged event: true unless its key is already in the recently-seen set.
  # The key is `{tag, row.id}` (a durable row always has an id, so the two topic deliveries share
  # it); a row with no id falls back to the whole `{tag, row}` term.
  defp fresh?(state, tag, row), do: seen_key(tag, row) not in state.seen_events

  defp seen_key(tag, %{id: id}) when not is_nil(id), do: {tag, id}
  defp seen_key(tag, row), do: {tag, row}

  defp cap_seen(keys), do: Enum.take(keys, @seen_cap)

  # Operator-relevant Bus events become native desktop notifications via an OSC 777 escape —
  # ghostty (Linux and macOS) raises it as a real notification, and only when unfocused (the
  # terminal owns focus policy). Best-effort: a host that ignores OSC 777 ignores the bytes.
  defp desktop_notify(tag, row) do
    with {title, body} <- Aleph.Notify.for_event(tag, row) do
      _ = File.write("/dev/tty", Aleph.Notify.osc(title, body))
    end

    :ok
  end

  # A machine LEAF closing nudges the tertius center to refresh the rollup — the "a leaf
  # finished" synthesis trigger. The root closing is not a leaf finish. Best-effort; tertius not up
  # (or not yet captured) = no-op. (record_done-without-close is a future trigger — its Bus event is
  # thread-scoped, so it doesn't reach the cockpit globally the way :thread_closed does.)
  defp nudge_tertius_on_finish(:thread_closed, %{scope: "machine", id: id}, %{standing_thread_id: root} = state)
       when is_integer(root) and is_integer(id) and id != root do
    world_id = active_world_id(state)

    case tlon_window_index(world_id, lead_window_name(world_id)) do
      nil ->
        :ok

      index ->
        inject_turn(world_id, index, "[funes] leaf ##{id} finished — run machine_overview and refresh the root rollup.")
    end
  end

  defp nudge_tertius_on_finish(_tag, _row, _state), do: :ok

  # @-mention delivery: a posted message naming a coworker (`@tertius-machine` / `@claude-machine`) is
  # injected as a turn into that coworker's tmux window, so a cold pane gets woken instead of silently
  # accumulating an unread thread. Pure routing lives in Aleph.Mention; this is the edge — best-effort
  # tmux send-keys, never a crash on a missing window.
  defp mention_notify(row, state) do
    lead = thread_lead(row)
    world_id = active_world_id(state)

    case delivery_target(row, state, lead) do
      :skip ->
        :ok

      {:route, staffed} ->
        for {window, text} <- Aleph.Mention.route(row, [lead: lead, staffed_window: staffed], active_roster(world_id)),
            index = tlon_window_index(world_id, window),
            not is_nil(index) do
          inject_turn(world_id, index, text)
        end

        :ok
    end
  end

  # Which window a posted message wakes, and whether to wake at all. Every staffed machine thread
  # has its OWN `t<id>` window, so routing depends on which case applies:
  #   * the standing coworker's thread → route globally (`staffed_window: nil`); its lead already
  #     runs in the base `claude`/`pi` window.
  #   * a claude-led staffed thread that's live AND past its opening turn → route onto `t<id>`, so
  #     replies reach the session working THAT thread — not the standing coworker (otherwise both
  #     the `t2` session and the standing `claude` would answer the same post).
  #   * a claude-led staffed thread mid-spawn / pre-opening → `:skip`: `ensure_thread_sessions`
  #     owns the opening turn (two-phase, race-safe); waking here would double it.
  #   * no staffed lead, or a pi-led thread (no window spawned for it) → route globally.
  defp delivery_target(%{thread_id: tid}, state, lead) when is_integer(tid) do
    standing = state.standing_thread_id || machine_thread_id()

    cond do
      tid == standing -> {:route, nil}
      is_nil(lead) or not claude_launched?(lead, active_world_id(state)) -> {:route, nil}
      staffed_thread_ready?(tid, state) -> {:route, "t#{tid}"}
      true -> :skip
    end
  end

  defp delivery_target(_row, _state, _lead), do: {:route, nil}

  # A claude-led staffed thread whose `t<id>` window is live and whose opening turn has already
  # been submitted (`ensure_thread_sessions` set `opening_injected`) — so `mention_notify` may
  # deliver subsequent turns straight to it without racing or doubling the opening.
  defp staffed_thread_ready?(tid, state),
    do: MapSet.member?(state.opening_injected, tid) and not is_nil(tlon_window_index(active_world_id(state), "t#{tid}"))

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

  # The tmux target world id for a call site that only has `state` (not a `Space.world?`-guarded
  # `active_key`) in scope — a background Bus handler, or a click that landed on a World-only panel.
  # `state.active_key` when it names a World, else the funes-down/no-active-world fallback
  # (`Space.first_world/0`) — the same degradation `tlon_tmux/2` falls back to.
  defp active_world_id(%{active_key: key}) when Space.world?(key), do: key

  defp active_world_id(_state) do
    case Space.first_world() do
      nil -> nil
      space -> space.id
    end
  end

  # The active roster's LEAD window name (the center's tab label) for `world_id`, or nil (no roster
  # / funes down).
  defp lead_window_name(world_id) do
    case Space.fetch(world_id) do
      %Space{roster: [lead | _]} -> roster_entry(lead).name
      _ -> nil
    end
  end

  # A roster entry (funes JSON `%{"archetype" => "builder", "name" => "hronir"}`, or a test's atom-keyed
  # `%{archetype: :builder, name: "hronir"}`) normalized to `%{archetype: atom, name: string}` —
  # `Profiles.instantiate/1`'s input shape. Read tolerantly (either key style); an archetype STRING
  # (funes JSON) is the wire form, normalized to the atom the archetype registry is keyed by.
  defp roster_entry(entry) do
    %{
      archetype: normalize_archetype(entry["archetype"] || entry[:archetype]),
      name: entry["name"] || entry[:name]
    }
  end

  defp normalize_archetype(a) when is_atom(a), do: a

  # NOT `String.to_existing_atom/1`: that only succeeds once something else has already loaded
  # `Aleph.Profiles` (interning `:builder`/`:surveyor`/…) into the atom table — an ordering
  # accident, not a guarantee (a fresh boot / an isolated test can hit this BEFORE anything else
  # touches Profiles). Resolving against the compiled archetype registry instead forces that load
  # as an ordinary qualified call, and is exhaustion-safe the same way (a bounded, compiled set).
  defp normalize_archetype(a) when is_binary(a),
    do: Enum.find(Map.keys(Profiles.archetypes()), &(Atom.to_string(&1) == a))

  # The tmux window index for a named coworker window in world `world_id`, from the live session
  # (nil if not up).
  defp tlon_window_index(world_id, name), do: window_index(tlon_tabs(world_id), name)

  # Same lookup against an already-fetched tabs list — for a caller (`ensure_thread_sessions`)
  # that snapshot tlon_tabs() once for a whole render pass instead of forking `tmux` per thread.
  defp window_index(tabs, name) do
    Enum.find_value(tabs, fn %{name: n, index: index} -> if n == name, do: index end)
  end

  # Inject `text` as a submitted turn into window `index` of world `world_id`: literal text, then
  # the Enter key — so a multiline body flattened to one line reaches the coworker's input as a
  # single message. Safe for a LONG-BOOTED window (the standing coworkers); a freshly-spawned
  # harness needs the split form below (`inject_text`/`submit_turn`) so the Enter doesn't get
  # swallowed in the same input burst.
  defp inject_turn(world_id, index, text) do
    inject_text(world_id, index, text)
    submit_turn(world_id, index)
  end

  # Type literal `text` into window `index` of world `world_id` WITHOUT submitting — the first half
  # of a fresh-window inject, so the Enter can be sent on a later render once the TUI has settled.
  defp inject_text(world_id, index, text) do
    _ =
      System.cmd(
        "tmux",
        tlon_tmux(world_id, ["send-keys", "-l", "-t", "#{world_session(world_id)}:#{index}", text]),
        stderr_to_stdout: true
      )

    :ok
  end

  # Send Enter to window `index` of world `world_id` — submits whatever's in its input. Split from
  # `inject_text` so a just-booted Claude Code TUI gets the text and the Enter as separate bursts (a
  # bundled Enter lands as a literal newline / gets swallowed, leaving the turn typed-but-unsent).
  defp submit_turn(world_id, index) do
    _ =
      System.cmd(
        "tmux",
        tlon_tmux(world_id, ["send-keys", "-t", "#{world_session(world_id)}:#{index}", "Enter"]),
        stderr_to_stdout: true
      )

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

  # Clicking the center terminal: forward to the PTY when the embedded program tracks the mouse
  # (tmux `mouse on` selects; a TUI hit-tests its own regions). The terminal renders edge-to-edge —
  # the Tlön window strip is WindowBar's own bordered panel above it (see the next clause), so
  # there is no row-0 special case here anymore.
  defp dispatch_click({Panel.Terminal, _data, rect}, x, y, state) do
    with term when is_pid(term) <- center_terminal(state) do
      Terminal.mouse(term, :press, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
    end

    {:noreply, state}
  end

  # Clicking a WindowBar tab selects that tmux window — never forwarded to the PTY (WindowBar is a
  # standalone panel, not part of the terminal it frames). WindowBar tabs are leader windows only,
  # so a hit resets focused_session to that leader (clears a stale {:leaf, id} — C3.3).
  defp dispatch_click({WindowBar, data, rect}, x, _y, state) do
    tab = WindowBar.tab_at_x(data[:tabs] || [], x - rect.x)
    select_tlon_window(active_world_id(state), tab)
    state = if tab, do: %{state | focused_session: {:leader, tab[:name]}}, else: state
    {:noreply, render(state)}
  end

  defp dispatch_click({panel, data, rect}, _x, y, state), do: apply_pick(Panel.pick(panel, data, rect, y - rect.y), state)

  # Select a Tlön tmux window in world `world_id` by the clicked/hovered tab's index; nil (past the
  # tabs) is a no-op.
  defp select_tlon_window(world_id, %{index: idx}) do
    tlon_run(world_id, ["select-window", "-t", "#{world_session(world_id)}:#{idx}"])
    :ok
  end

  defp select_tlon_window(_world_id, _tab), do: :ok

  # A drag/release over the terminal body → the PTY; anywhere else is ignored. The terminal is
  # edge-to-edge now, so there is no tab-row offset to shift by.
  defp forward_terminal_mouse({Panel.Terminal, _data, rect}, action, x, y, state) do
    with term when is_pid(term) <- center_terminal(state) do
      Terminal.mouse(term, action, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
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
  # UNREFERENCED since Slice 0 collapse (Sessions deleted) — no keymap clause emits :enter_or_spawn
  # now; kept intact, teardown TBD.
  defp apply_effect({:enter_or_spawn, thread_id}, state),
    do: {:noreply, render(%{state | flash: enter_or_spawn(thread_id, state)})}

  # The `m` verb landed: advance the coworker's driver model one step round the ring and persist
  # it (Aleph.Config). Honest about scope: the RUNNING coworker keeps its model — the override
  # applies wherever Profiles.fetch flows on the next spawn (aleph:reset, or kill the pi window).
  defp apply_effect({:cycle_coworker_model, profile_name}, state) do
    {:noreply, render(%{state | flash: cycle_model!(profile_name)})}
  rescue
    e -> {:noreply, render(%{state | flash: "settings write failed: #{Exception.message(e)}"})}
  end

  # The settings modal applied a change to the selected coworker: cycle its driver model, or flip
  # its yolo (permission) policy. Same honest scope as the `m` verb — the running coworker keeps its
  # config; the override lands on the next spawn. The modal stays open (state.modal untouched).
  defp apply_effect({:settings_apply, {profile_name, :model}}, state) do
    {:noreply, render(%{state | flash: cycle_model!(profile_name)})}
  rescue
    e -> {:noreply, render(%{state | flash: "settings write failed: #{Exception.message(e)}"})}
  end

  defp apply_effect({:settings_apply, {profile_name, :permission}}, state) do
    case Settings.next_yolo(Profiles.fetch(profile_name).permissions) do
      {:ok, next, policy} ->
        Aleph.Config.put_coworker_yolo(profile_name, next)

        {:noreply,
         render(%{state | flash: "#{profile_name} permissions → #{policy} — applies on next spawn (aleph:reset)"})}

      :no_policy ->
        {:noreply, render(%{state | flash: "#{profile_name} has no permission policy to toggle"})}
    end
  rescue
    e -> {:noreply, render(%{state | flash: "settings write failed: #{Exception.message(e)}"})}
  end

  # Enter in Tlön nav: on SPACES, switch to the lens under the cursor; on Leaves, attach the leaf's
  # live World window in the center (preview + commit); on any other pane, open its selection's
  # detail in MAIN (set focus.detail?, which the View renders).
  defp apply_effect(:tlon_enter, state) do
    layout = tlon_layout(state)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Spaces -> apply_pick({:switch_space, space_at_cursor(state, layout)}, state)
      Panel.Leaves -> jump_to_leaf(state, layout)
      _ -> {:noreply, render(put_in(state.focus.detail?, true))}
    end
  end

  # A hover in Tlön nav (`:tlon_preview`): re-point the World center to the window under the cursor
  # (a live preview) WITHOUT taking focus or sending keys — commit does that. See preview_focused/1.
  defp apply_effect(:tlon_preview, state), do: {:noreply, render(preview_focused(state))}

  # `[`/`]` landed (C3.4): step the World's right-pane view and repaint.
  defp apply_effect({:cycle_pane_view, dir}, state), do: {:noreply, render(cycle_pane_view(state, dir))}

  # a/r on Memory's habits section: resolve the selected pending habit from the focus + cached read,
  # act via funes, then null the memory cache so the pane reflects the shrunk queue on next render.
  # A no-op (flash only) if the focus isn't on a selectable habit.
  defp apply_effect({:habit_action, action}, state) do
    case selected_habit(state) do
      nil ->
        {:noreply, render(%{state | flash: "no habit selected — Tab to HABITS, j/k to pick"})}

      habit ->
        {verb, result} =
          case action do
            :approve -> {"approved", Funes.approve_habit(habit.id)}
            :reject -> {"rejected", Funes.reject_habit(habit.id)}
          end

        flash =
          case result do
            {:ok, _} -> "habit #{verb}"
            _ -> "couldn't #{action} habit"
          end

        {:noreply, render(%{state | memory: nil, flash: flash})}
    end
  rescue
    e -> {:noreply, render(%{state | flash: "habit action failed: #{Exception.message(e)}"})}
  end

  @doc false
  # The pure decision behind `[`/`]`: advance `right_pane_view` by `dir`, wrapped at the active
  # space's right-column length (0 → no right column → no-op, guards div-by-zero). Public + exposed
  # (like `attach_leaf/2`/`preview_focused/1`) so it's testable without a live GenServer.
  def cycle_pane_view(%{active_key: key} = state, dir) when Space.world?(key) do
    case Space.fetch(key) do
      %{right: right} when right != [] ->
        n = length(right)
        %{state | right_pane_view: rem(state.right_pane_view + dir + n, n)}

      _ ->
        state
    end
  end

  def cycle_pane_view(state, _dir), do: state

  # The pending habit the focus points at, or nil unless: a World space, nav mode, Memory pane,
  # habits section (1), with a habit under the clamped cursor.
  defp selected_habit(
         %{active_key: key, memory: %{habits: habits}, focus: %{in_terminal?: false, section: 1} = focus} = state
       )
       when Space.world?(key) do
    layout = tlon_layout(state)
    if Focus.focused_pane(focus, layout) == Panel.Memory, do: Enum.at(habits, Focus.cursor(focus, layout))
  end

  defp selected_habit(_state), do: nil

  # The selected leaf → attach its live World window in the center (Worlds Slice 0): the Enter path
  # of the preview-swap. render is un-unit-testable (it paints via termbox); attach_leaf/2 is the
  # pure decision, so it carries the logic + tests.
  defp jump_to_leaf(state, layout), do: {:noreply, render(attach_leaf(state, layout))}

  @doc false
  # PREVIEW (re-point) then COMMIT (focus in) the World tmux window under the Leaves cursor. C3.3:
  # a leaf is now a real attachable session — prefer ITS OWN `t<id>` window over its lead's, so
  # `focused_session` becomes `{:leaf, id}`. Falls back to the lead's window (today's Slice-0
  # behavior, `focused_session: {:leader, lead}`) when the leaf has no live window of its own. Both
  # lookups run off ONE `tlon_tabs()` snapshot: resolve `idx`, then `select_tlon_window` + commit
  # against that same idx — never a second read that could disagree (a TOCTOU half-attach if a
  # window vanished between two snapshots). No leaf under the cursor, or no window either way, can't
  # attach yet: flash the deferral, re-point nothing. Supersedes the old jump into the retiring
  # Sessions space. Note: `preview_focused/1` (the arrow-hover path) is deliberately NOT reused here
  # — it takes its own snapshot, which is safe for its single read but would reintroduce the double
  # read.
  def attach_leaf(state, layout) do
    rows = (state.leaves || %{rows: []}).rows
    world_id = active_world_id(state)

    case Enum.at(rows, Focus.cursor(state.focus, layout)) do
      %{id: id, lead: lead} ->
        tabs = tlon_tabs(world_id)

        case {window_index(tabs, "t#{id}"), window_index(tabs, lead)} do
          {idx, _} when not is_nil(idx) ->
            select_tlon_window(world_id, %{index: idx})

            state
            |> Map.put(:previewed_window, idx)
            |> commit_preview()
            |> Map.merge(%{focused_session: {:leaf, id}, flash: nil})

          {nil, idx} when not is_nil(idx) ->
            select_tlon_window(world_id, %{index: idx})

            state
            |> Map.put(:previewed_window, idx)
            |> commit_preview()
            |> Map.merge(%{focused_session: {:leader, lead}, flash: nil})

          _ ->
            %{state | flash: "no live session (Slice 1)"}
        end

      _ ->
        %{state | flash: "no live session (Slice 1)"}
    end
  end

  @doc false
  # Preview-swap (Worlds Slice 0, tweak #1): re-point the World center to the tmux window under the
  # nav cursor, storing it in `previewed_window`, WITHOUT taking keyboard focus (in_terminal? stays
  # put) or sending keys — a live preview that follows the selection. Only a window-bearing pane
  # (Leaves, mapped by the leaf's lead to a live window) re-points; a leaf with no live window, or
  # any other pane/space, leaves the center exactly where it was. commit_preview/1 is what focuses.
  def preview_focused(%{active_key: key} = state) when Space.world?(key) do
    layout = tlon_layout(state)
    rows = (state.leaves || %{rows: []}).rows

    with Panel.Leaves <- Focus.focused_pane(state.focus, layout),
         %{lead: lead} <- Enum.at(rows, Focus.cursor(state.focus, layout)),
         idx when not is_nil(idx) <- window_index(tlon_tabs(key), lead) do
      select_tlon_window(key, %{index: idx})
      %{state | previewed_window: idx}
    else
      _ -> state
    end
  end

  def preview_focused(state), do: state

  @doc false
  # Commit the previewed World window: take keyboard focus into the center (in_terminal? true) so
  # keystrokes now flow to tmux. The shared "attach in place" step — Task 2's Leaves-Enter reuses it.
  def commit_preview(state), do: put_in(state.focus.in_terminal?, true)

  # `enter_or_spawn`: if the focused thread already has a live session, it's already the center —
  # nothing to do (you're already working there). Otherwise spawn one onto it — one `spawn_onto/2`
  # path, reached via `n` (new thread) or `Enter` (existing).
  # UNREFERENCED since Slice 0 collapse (Sessions deleted) — the `Enter`-to-spawn path is gone; the
  # `n`/new-thread path still calls spawn_onto/2 directly. Kept intact, teardown TBD.
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
    # Fill the probe cache (Tlön only) and find-or-spawn the World's roster — both stateful,
    # both rate-limited, both OUT of the per-frame hot path.
    state =
      state
      |> ensure_probes()
      |> ensure_world_roster()
      |> ensure_log_window()
      |> ensure_thread_sessions()

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
      worlds: if(state.active_key == :orbis, do: orbis_worlds(state), else: []),
      terminal: terminal_read(state, focused),
      machine: machine_read(state),
      stack: state.stack || @empty_stack,
      health: state.health,
      activity: state.activity,
      memory: if(Space.world?(state.active_key), do: state.memory),
      orbis: if(Space.world?(state.active_key), do: state.leaves),
      focused_session: state.focused_session,
      # Which of the World's right-column panels (Health/Activity/Leaves) to show, full-height —
      # the `[`/`]` cycle (C3.4). View clamps with `rem`, so this is meaningless-but-harmless
      # outside a World.
      right_pane_view: state.right_pane_view,
      logbook: logbook_read(state.active_key),
      triage: if(state.active_key == :orbis, do: triage_read(threads)),
      habits: habits_read(state.active_key),
      settings: settings_read(state.active_key),
      scrolls: state.scrolls,
      input: state.input,
      modal: settings_modal_read(state),
      flash: state.flash,
      leader_pending?: state.leader_pending?,
      # The World space's focus, so the View can light the focused sidebar pane and the status bar
      # can show NAV/TERM. nil elsewhere — no other space navigates panes this way.
      focus: if(Space.world?(state.active_key), do: state.focus),
      # The layout the View reads for the focused pane + item cursor (counts), and the resolved
      # MAIN detail (nil unless the focus opened one). Both nil outside a World space.
      tlon_layout: if(Space.world?(state.active_key), do: tlon_layout(state)),
      detail: if(Space.world?(state.active_key) and state.focus.detail?, do: tlon_detail(state, tlon_layout(state)))
    }

    placements = View.compose(reads, state.w, state.h)

    placements
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    %{state | placements: placements}
  end

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # No space carries a per-thread native-PTY center since the Slice 0 collapse (Sessions deleted);
  # Tlön's center reads via machine_read, so terminal_read is uniformly `:no_session`.
  defp terminal_read(_state, _focused), do: :no_session

  # The Tlön center's read: the embedded tmux client. Lookup only — the find-or-spawn lives in
  # ensure_center (render's stateful preamble, via ensure_world_roster), so a failing spawn can back
  # off instead of re-materialising the profile and re-issuing tmux new-session every frame.
  defp machine_read(%{active_key: key}) when Space.world?(key) do
    case render_state_of(safe_terminal(:machine)) do
      %{} = render_state -> Map.put(render_state, :tabs, tlon_tabs(key))
      other -> other
    end
  end

  defp machine_read(_state), do: :no_session

  defp render_state_of(nil), do: :no_session
  defp render_state_of(term), do: Terminal.render_state(term)

  # Sessions is supervised (Aleph.Supervisor) but the cockpit is NOT — a `Sessions.terminal/1`
  # against a torn-down registry raises `(EXIT) no process`, which would otherwise propagate up
  # through render and kill the cockpit, wedging all input (Enter would go nowhere). Degrade to
  # nil so a dead registry just reads as "no session"; the supervisor restarts it on its own.
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

  # The terminal that owns the keys, by space: a World → the embedded tmux client (still the single
  # `:machine` registry entry in Slice 1 — C2 keys the terminal per world id). nil elsewhere (Orbis
  # has no center Terminal — its surface is the Chorus).
  defp center_terminal(%{active_key: key}) when Space.world?(key), do: safe_terminal(:machine)
  defp center_terminal(_state), do: nil

  # The thread `c` composes onto, derived per keypress (like center_live?): the focused project
  # thread in Orbis; in a World space the MACHINE thread — the operator working the box posts to
  # the machine coworker, never a stale project thread id carried over from Orbis. nil (no thread)
  # makes `c` a no-op.
  defp composer_thread_id(%{active_key: key}) when Space.world?(key), do: machine_thread_id()
  defp composer_thread_id(state), do: state.focused_id

  # The shape the Tlön focus SM navigates: the space's two sidebar columns, per-pane section counts
  # (empty until a multi-section pane lands — Memory's coverage/floor/habits split), and per-pane
  # ITEM counts (what j/k clamps against), derived from the live reads in `state`. Keyed by pane
  # module, matching space.left/right. nil-ish layout for other spaces (the keymap only reads it in
  # Tlön anyway).
  # SPACES leads the left column in the FOCUS layout exactly as it does on screen (View prepends it
  # to `space.left`), so `h`/`H` can land on the space-switcher and `Enter` there switches lens.
  defp tlon_layout(%{active_key: key} = state) when Space.world?(key) do
    case Space.fetch(key) do
      # A stale/removed active_key mid-render (Space.fetch/1 returns nil on a miss) — degrade to
      # the same empty layout a non-World space gets, rather than crash the render.
      nil ->
        %{left: [], right: [], sections: %{}, counts: %{}}

      space ->
        %{
          left: [Panel.Spaces | space.left],
          right: space.right,
          sections: %{Panel.Memory => 2},
          counts: pane_counts(state)
        }
    end
  end

  defp tlon_layout(_state), do: %{left: [], right: [], sections: %{}, counts: %{}}

  defp space_at_cursor(state, layout), do: Enum.at(Space.all(), Focus.cursor(state.focus, layout)).key

  # The navigable item count per pane, for j/k clamping. Commits = the commit-log length; Memory is
  # sectioned — j/k walks the ACTIVE section's list (floor=0, habits=1), so its count follows
  # focus.section. Panes without a list are absent (0 → j/k is a no-op there).
  defp pane_counts(state) do
    %{
      Panel.Spaces => length(Space.all()),
      Panel.Stack => length((state.stack || @empty_stack).commits),
      Panel.Memory => memory_section_count(state),
      Panel.Leaves => leaf_count(state.leaves)
    }
  end

  defp leaf_count(%{rows: rows}), do: length(rows)
  defp leaf_count(_), do: 0

  defp memory_section_count(%{memory: nil}), do: 0
  defp memory_section_count(%{focus: %{section: 1}, memory: m}), do: length(m.habits)
  defp memory_section_count(%{memory: m}), do: length(m.floor)

  # MAIN's detail for the focused pane's current selection, or nil (this pane has no detail, or
  # nothing is selected) → the terminal stays. Dispatch per pane; Commits resolves the selected
  # commit's diff via Aleph.Stack.show, Memory the selected floor fact / pending habit.
  defp tlon_detail(state, layout) do
    case Focus.focused_pane(state.focus, layout) do
      Panel.Stack -> commit_detail(state, Focus.cursor(state.focus, layout))
      Panel.Memory -> memory_detail(state, Focus.cursor(state.focus, layout))
      _ -> nil
    end
  end

  # Section 0 (floor) → the selected fact's full text + metadata; section 1 (habits) → the selected
  # habit's text + rationale. nil (empty section / no memory) leaves the terminal up.
  defp memory_detail(%{memory: nil}, _index), do: nil

  defp memory_detail(%{focus: %{section: 1}, memory: m}, index), do: habit_detail(Enum.at(m.habits, index))
  defp memory_detail(%{memory: m}, index), do: fact_detail(Enum.at(m.floor, index))

  defp fact_detail(nil), do: nil

  defp fact_detail(fact) do
    meta =
      [{"kind: #{fact.kind}  ·  #{fact.provenance}", :dim}] ++
        for {label, val} <- [{"check", fact.check_cmd}, {"incident", fact.incident}, {"taught", fact.taught}],
            is_binary(val) and val != "",
            do: {"#{label}: #{val}", :dim}

    %{title: "FLOOR FACT", lines: [{"", :normal}, {fact.text, :normal}, {"", :normal} | meta]}
  end

  defp habit_detail(nil), do: nil

  defp habit_detail(habit) do
    by = if is_binary(habit.proposed_by), do: "  ·  proposed by #{habit.proposed_by}", else: ""

    rationale =
      if is_binary(habit.rationale) and habit.rationale != "", do: [{"", :normal}, {habit.rationale, :dim}], else: []

    %{title: "PENDING HABIT#{by}", lines: [{"", :normal}, {habit.text, :normal} | rationale]}
  end

  defp commit_detail(state, index) do
    case Enum.at((state.stack || @empty_stack).commits, index) do
      %{hash: hash, subject: subject} ->
        %{title: "commit #{hash} · #{subject}", lines: Enum.map(Aleph.Stack.show(hash), &diff_line/1)}

      nil ->
        nil
    end
  end

  defp diff_line(%{text: text, kind: kind}), do: {text, diff_style(kind)}
  defp diff_style(:add), do: :diff_add
  defp diff_style(:del), do: :diff_del
  defp diff_style(:hunk), do: :diff_hunk
  defp diff_style(:file), do: :label
  defp diff_style(:meta), do: :dim
  defp diff_style(:context), do: :normal

  defp machine_thread_id do
    case Channel.machine_thread() do
      %{id: id} -> id
      _ -> nil
    end
  end

  # Expire cached probes once @probe_ms has passed; render's ensure_probes refills lazily.
  defp maybe_expire_probes(state) do
    if System.monotonic_time(:millisecond) - state.probed_at >= @probe_ms do
      %{state | stack: nil, health: nil, memory: nil, leaves: nil}
    else
      state
    end
  end

  # Fill the probe cache when a World space is active and the cache is cold. Elsewhere the probes
  # stay nil — git/nix/df/tmux forks and funes reads are wasted on spaces that never show them.
  defp ensure_probes(%{active_key: key, stack: nil} = state) when Space.world?(key) do
    %{
      state
      | stack: stack_read(),
        health: health_read(),
        memory: memory_read(),
        leaves: orbis_read(key),
        probed_at: System.monotonic_time(:millisecond)
    }
  end

  # Orbis' survey only needs the rollup, not the git/nix/df battery — fill just the cached leaves
  # rollup on the SAME @probe_ms throttle so `orbis_worlds/1` reads the cache, never gathers funes
  # per-frame.
  defp ensure_probes(%{active_key: :orbis, leaves: nil} = state) do
    %{state | leaves: orbis_read(:orbis), probed_at: System.monotonic_time(:millisecond)}
  end

  defp ensure_probes(state), do: state

  # The Memory pane read: coverage stats + the always-loaded floor + the pending-habit queue.
  defp memory_read do
    %{coverage: Funes.recall_coverage(), floor: Funes.floor(), habits: Funes.pending_habits()}
  end

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
      tools: Aleph.Stack.tools(),
      version: Aleph.Stack.release()
    }
  end

  # HABITS reads are only gathered on a World space — the machine-wide review queue (pending) and
  # the always-loaded set (approved). Machine-wide, so not keyed on a focused thread.
  defp habits_read(key) when Space.world?(key),
    do: %{pending: Dossier.pending_habits(), approved: Dossier.approved_habits()}

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

  # Advance a coworker's driver one step round the ring and persist it; returns the flash string.
  defp cycle_model!(profile_name) do
    current = Profiles.fetch(profile_name)
    next = Profiles.next_model(current && current.model)
    Aleph.Config.put_coworker_model(profile_name, next)
    "coworker driver → #{next.provider}/#{next.model} — applies on next spawn (aleph:reset)"
  end

  # The settings-modal read: nil when closed, else the selection (row/field) plus a per-coworker row
  # — its effective model + ring + whether it's overridden + its yolo policy — for the overlay.
  defp settings_modal_read(%{modal: %Settings{open?: true} = m}) do
    %{row: m.row, field: m.field, rows: Enum.map(m.coworkers, &coworker_row/1)}
  end

  defp settings_modal_read(_state), do: nil

  defp coworker_row(name) do
    p = Profiles.fetch(name)

    %{
      profile: name,
      model: p.model,
      ring: Profiles.model_ring(),
      override?: Aleph.Config.coworker_model(name) != nil,
      yolo?: p.permissions && p.permissions["yoloMode"]
    }
  end

  # LOGBOOK reads are only gathered on a World space — the machine thread's issues + recent
  # messages, the shared notebook for notes and observations about the env.
  defp logbook_read(key) when Space.world?(key) do
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

  # ORBIS rollup (Orbis Tertius slice 2) — the machine-scoped vantage, gathered on the spaces that
  # show it (a World's LEAVES sidebar + Orbis' survey), cached in `state.leaves` on the @probe_ms
  # throttle. The semantics live in `Aleph.Orbis` (shared with the `chat` tab's header strip) so a
  # status rule never drifts between the surfaces.
  defp orbis_read(:orbis), do: Aleph.Orbis.rollup()
  defp orbis_read(key) when Space.world?(key), do: Aleph.Orbis.rollup()
  defp orbis_read(_key), do: nil

  # The Orbis survey (Chorus center): the per-WORLD rollup grouping (Slice 0: one hardcoded world).
  # Reads the SAME cached `state.leaves` rollup the @probe_ms throttle fills — its `worlds` key — so
  # the survey and the Tlön LEAVES sidebar share one gather. Empty list when funes is down / the
  # cache is cold / there are no worlds. Public: a pure read seam (unit-tested against a known cache).
  def orbis_worlds(state) do
    case state.leaves do
      %{worlds: worlds} -> worlds
      _ -> []
    end
  end

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

  # The World's cast, spawned lazily on entry from its roster (C2.3 — replaces the old hardcoded
  # ensure_machine_coworker/ensure_claude_coworker/ensure_third_coworker trio): head = the CENTER
  # (embedded terminal, `new-session`), tail = tmux windows (`new-window`), each launcher chosen by
  # its archetype's harness. An empty roster / funes-down space is a no-op. `spaces` defaults to the
  # live cache (`Space.all/0`, `render`'s call) but is overridable — mirrors `Space.fetch/1` vs
  # `/2` — so a test drives a roster without a live world in the funes DB.
  @doc false
  def ensure_world_roster(state, spaces \\ Space.all())

  def ensure_world_roster(%{active_key: key} = state, spaces) when Space.world?(key) do
    case Space.fetch(key, spaces) do
      %Space{roster: [lead | rest]} -> state |> ensure_center(key, lead) |> ensure_windows(key, rest)
      _ -> state
    end
  end

  def ensure_world_roster(state, _spaces), do: state

  # The roster LEAD: a pi session working ON the box on a persistent "machine" thread (so its work
  # is triageable) — pi by design, claude stays the deliberate escalation (AGENTS.md routing).
  # Find-or-spawned here (render's stateful preamble), with a backoff: a failed spawn must not retry
  # the whole materialise+tmux pipeline on EVERY render — that would be a spawn storm whenever the
  # coworker can't start.
  defp ensure_center(state, world_id, lead) do
    now = System.monotonic_time(:millisecond)

    cond do
      is_pid(safe_terminal(:machine)) ->
        state

      not machine_spawn_due?(state.machine_retry_at, now) ->
        state

      true ->
        case spawn_center(world_id, lead) do
          pid when is_pid(pid) -> capture_standing_thread_id(state)
          _ -> %{state | machine_retry_at: now + @machine_spawn_backoff_ms}
        end
    end
  end

  # Stash the standing coworker's machine thread id, once, at its first successful spawn —
  # the id `ensure_thread_sessions` excludes from its own spawn pass (the standing center
  # coworker is not "a staffed machine thread it should spawn a session for", it already has one).
  defp capture_standing_thread_id(%{standing_thread_id: nil} = state),
    do: %{state | standing_thread_id: machine_thread_id()}

  defp capture_standing_thread_id(state), do: state

  # The roster TAIL: one tmux window per entry, each a second window in the SAME session as the
  # center, joined to the SAME root thread, so the cast coordinates over funes messages like any
  # two agents. Gated on the center up (its spawn opens/finds the root thread these join) and on
  # the window not already being there (tmux `new-window` isn't idempotent like `new-session -A` —
  # a naive re-run every render would spawn a fresh coworker every tick).
  defp ensure_windows(state, world_id, entries) do
    if is_pid(safe_terminal(:machine)) do
      existing = world_id |> tlon_tabs() |> MapSet.new(& &1.name)

      entries
      |> Enum.map(&roster_entry/1)
      |> Enum.reject(&MapSet.member?(existing, &1.name))
      |> Enum.each(fn %{archetype: arch, name: name} ->
        spawn_window(world_id, Profiles.instantiate(%{archetype: arch, name: name}))
      end)
    end

    state
  end

  # Dispatch a tail window's launcher by its archetype's harness — real Claude (honestly
  # identified, no pi-multi-account impersonation — see Aleph.Profiles' @seed_roster comment) or a
  # windowed pi.
  defp spawn_window(world_id, %Profile{harness: :claude_code, name: name}),
    do: spawn_agent_window(world_id, "#{name}-machine", name)

  defp spawn_window(world_id, %Profile{harness: :pi} = profile), do: spawn_pi_window(world_id, profile, profile.name)

  # The `chat` tab (the third Tlön window): the INTERACTIVE machine-chat — machine-scope threads as
  # foldable blocks with author-turn grouping (fold/zoom/scroll), so the tertius/hronir tabs can stay
  # their raw harness selves. NOT a coworker — no funes identity, no wake-loop entry (Aleph.Mention
  # doesn't know it); it just polls the db the cockpit writes. Gated like the claude window: pi up
  # (so a machine thread exists to read), window absent (`new-window` isn't idempotent), retried each
  # render — a failed open just leaves the tab missing.
  defp ensure_log_window(%{active_key: key} = state) when Space.world?(key) do
    cond do
      not is_pid(safe_terminal(:machine)) -> state
      Enum.any?(tlon_tabs(key), &(&1.name == "uqbar")) -> state
      true -> spawn_log_window(key) && state
    end
  end

  defp ensure_log_window(state), do: state

  # A staffed-but-session-less machine thread gets its own tmux window (`t<id>`), so a
  # thread the operator opened outside the standing tertius/hronir coworkers gets a live coworker
  # working IT specifically, not just accumulating unread messages. Two-phase, like the coworker
  # windows: `new-window` first (this pass), the opening turn only injected on a LATER render once
  # the window shows up live in `tlon_tabs()` — send-keys the instant `new-window` returns races
  # the harness's own boot and the first turn lands on the floor.
  #
  # Restricted to claude-launched leads (`claude_launched?/2`) — `spawn_agent_window` runs
  # `claude_launcher()`, so it is only correct for a roster :claude_code lead or the third-agent.
  # Pi-launched staffing is a follow-up.
  defp ensure_thread_sessions(%{active_key: key} = state) when Space.world?(key) do
    tabs = tlon_tabs(key)
    now = System.monotonic_time(:millisecond)

    Enum.reduce(Funes.staffed_machine_threads(), state, &ensure_thread_session(key, &1, tabs, now, &2))
  end

  defp ensure_thread_sessions(state), do: state

  defp ensure_thread_session(world_id, %{id: id, lead: lead}, tabs, now, state) do
    window = "t#{id}"

    cond do
      # The standing coworker's own thread — it already has a session (pi's/claude's window),
      # just not one named `t<id>`. Never spawn a duplicate for it.
      id == state.standing_thread_id ->
        state

      Enum.any?(tabs, &(&1.name == window)) ->
        maybe_inject_opening_turn(world_id, id, tabs, now, state)

      not claude_launched?(lead, world_id) ->
        state

      not thread_spawn_due?(state.thread_spawn_retry[id], now) ->
        state

      true ->
        record_thread_spawn(spawn_agent_window(world_id, lead, window, id), state, id, now)
    end
  end

  defp record_thread_spawn({_out, 0}, state, id, _now),
    do: %{state | thread_spawn_retry: Map.delete(state.thread_spawn_retry, id)}

  defp record_thread_spawn(_result, state, id, now),
    do: %{state | thread_spawn_retry: Map.put(state.thread_spawn_retry, id, now + @thread_spawn_backoff_ms)}

  # Is a per-thread session spawn attempt due? Mirrors `machine_spawn_due?/2` — nil means "no
  # backoff pending, try now".
  defp thread_spawn_due?(nil, _now), do: true
  defp thread_spawn_due?(retry_at, now), do: now >= retry_at

  # `spawn_agent_window` always runs claude_launcher() — correct only for a roster :claude_code lead
  # (this World's builder handle, roster-derived). A pi-led thread is skipped.
  defp claude_launched?(lead, world_id), do: lead in claude_handles(world_id)

  # The funes handles this World's roster stamps onto a `:claude_code`-harness archetype
  # (`"<name>-machine"`, e.g. the builder → `hronir-machine`) — the set `claude_launched?/2` checks
  # against.
  defp claude_handles(world_id), do: Enum.flat_map(active_roster(world_id), &claude_handle_if_claude_code/1)

  # This World's roster (`Aleph.Mention.route/3`'s resolution fixture) — funes-down / no roster
  # degrades to `[]` (nobody resolves, nobody wakes).
  defp active_roster(world_id) do
    case Space.fetch(world_id) do
      %Space{roster: roster} -> roster
      _ -> []
    end
  end

  defp claude_handle_if_claude_code(entry) do
    %{archetype: arch, name: name} = roster_entry(entry)
    if Profiles.instantiate(%{archetype: arch, name: name}).harness == :claude_code, do: ["#{name}-machine"], else: []
  end

  # Two-phase, so a just-booted `t<id>` window submits its opening turn instead of leaving it typed
  # but unsent: stage 1 types the text and records the moment; stage 2, once the text has settled
  # for @opening_submit_delay_ms, sends Enter and marks the thread done. Ordered newest-first: the
  # `opening_injected` (done) check must precede the `opening_text_at` (typed) check.
  defp maybe_inject_opening_turn(world_id, id, tabs, now, state) do
    cond do
      MapSet.member?(state.opening_injected, id) ->
        state

      Map.has_key?(state.opening_text_at, id) ->
        if now - state.opening_text_at[id] >= @opening_submit_delay_ms do
          with index when not is_nil(index) <- window_index(tabs, "t#{id}"), do: submit_turn(world_id, index)
          %{state | opening_injected: MapSet.put(state.opening_injected, id)}
        else
          state
        end

      true ->
        inject_opening_text(world_id, id, tabs)
        %{state | opening_text_at: Map.put(state.opening_text_at, id, now)}
    end
  end

  # Type the thread's latest operator message into its just-appeared `t<id>` window (no Enter yet —
  # stage 2 submits). Best-effort on both reads: a window that vanished between the tabs snapshot
  # and here, or a thread with no operator message yet, is silently skipped — never a render crash.
  defp inject_opening_text(world_id, id, tabs) do
    index = window_index(tabs, "t#{id}")
    message = Funes.latest_operator_message(id)

    if index && message do
      operator = Application.get_env(:funes, :operator, "andrew")
      inject_text(world_id, index, "[funes thread ##{id}] #{operator}: #{one_line(message.body)}")
    end

    :ok
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")

  # Open the `uqbar` window (the operator's console) running `mix aleph.machine_chat` from the aleph
  # project (where mise/mix resolve). It inherits the tlon session's `FUNES_DB`, so it reads the SAME
  # db the cockpit writes — the whole point of the poll-the-db design (a separate process can't share
  # the in-node Bus). Fire-and-forget: a failed spawn leaves the tab absent and the next render retries.
  defp spawn_log_window(world_id) do
    dir = Path.join(Profiles.repo(), "modules/aleph")
    script = "export TERM=xterm-256color\ncd #{dir}\nexec mise exec -- mix aleph.machine_chat"
    session = world_session(world_id)

    System.cmd("tmux", tlon_tmux(world_id, ["new-window", "-t", session, "-n", "uqbar", script]), stderr_to_stdout: true)
    # uqbar is the primary Tlön surface (the doorway), so seat it as tab 1: move it below base-index,
    # then renumber so it becomes the first window and tertius/hronir shift after it.
    System.cmd("tmux", tlon_tmux(world_id, ["move-window", "-s", "#{session}:uqbar", "-t", "#{session}:0"]),
      stderr_to_stdout: true
    )

    System.cmd("tmux", tlon_tmux(world_id, ["move-window", "-r", "-t", "#{session}:0"]), stderr_to_stdout: true)
  end

  # `tmux new-window`, not Sessions.spawn_harness: a roster tail entry rides as a window of the
  # ALREADY-embedded tlon tmux session (the center is window 0), not a separate Aleph.Terminal/PTY
  # of its own. Fire-and-forget: a failed spawn (funes down, no thread yet) just leaves the window
  # absent, and `ensure_windows` retries it on the next render — no backoff needed, `new-window` is
  # cheap and idempotent-by-absence-check above.

  # Open a Claude-Code window named `window` on `thread_id` as funes `agent`, in world `world_id` —
  # default `machine_thread_id()`, the standing coworkers' shared thread. The roster/third-experiment
  # windows AND the per-thread windows (`ensure_thread_sessions`) all ride this: same launcher,
  # distinct identity + tab label + (per-thread) distinct thread, so `FUNES_THREAD` binds the harness
  # to the thread it's actually meant to work on.
  defp spawn_agent_window(world_id, agent, window, thread_id \\ machine_thread_id())

  defp spawn_agent_window(world_id, agent, window, thread_id) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, agent, mandate: "machine") do
      script = "export TERM=xterm-256color\n" <> exports <> "\nexec " <> claude_launcher()
      # `-d`: spawn the window in the background — a coworker starting (a standing claude/third, or
      # a per-thread session) must NOT yank the operator off whatever window they're on.
      tlon_run(world_id, ["new-window", "-d", "-t", world_session(world_id), "-n", window, script])
    end
  end

  # The roster's :pi tail entries (a second surveyor/planner riding its own window, not the
  # embedded center): same shape as `spawn_agent_window`, but execs the bare `pi_command/1` instead
  # of `claude_launcher/0` — and its funes handle is the roster-derived `"<name>-machine"`.
  defp spawn_pi_window(world_id, profile, window, thread_id \\ machine_thread_id())

  defp spawn_pi_window(world_id, %Profile{name: name} = profile, window, thread_id) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, "#{name}-machine", mandate: "machine") do
      script = "export TERM=xterm-256color\n" <> exports <> "\nexec " <> pi_command(profile)
      tlon_run(world_id, ["new-window", "-d", "-t", world_session(world_id), "-n", window, script])
    end
  end

  defp claude_launcher, do: Path.join(Profiles.repo(), "modules/manos/claude-code/launch.sh")

  # The identity minter for a tail-window spawn — defaults to the live funes join (mints in-node
  # against the Repo/tokens), overridable via `:aleph, :tlon_join` so a test drives `ensure_windows`
  # against the SAME injected `:tlon_cmd` tmux runner without a live DB (mirrors `Aleph.Crew`'s
  # `:crew_join`/`:crew_cmd` pair).
  defp joiner, do: Application.get_env(:aleph, :tlon_join, &Spawn.join/3)

  @doc false
  # Is a machine-coworker spawn attempt due? `machine_retry_at` is nil until an attempt FAILS (the
  # "no backoff pending" sentinel — try now), then a future monotonic timestamp for @machine_spawn_backoff_ms.
  # It MUST be nil, not 0: BEAM monotonic time starts large-NEGATIVE, so `now < 0` reads as "still
  # backing off" forever and the coworker never spawns.
  def machine_spawn_due?(nil = _retry_at, _now), do: true
  def machine_spawn_due?(retry_at, now), do: now >= retry_at

  # Materialise the World's LEAD roster entry into a profile, find-or-create the machine identity,
  # then spawn the center: an embedded tmux client attached to the standing session (pi as window 0
  # if absent) — an aleph restart re-attaches to the running pi instead of spawning another.
  defp spawn_center(world_id, lead) do
    %{archetype: arch, name: name} = roster_entry(lead)

    with %Profile{} = profile <- Profiles.instantiate(%{archetype: arch, name: name}),
         {:ok, _dir} <- materialise_profile(profile),
         {:ok, exports} <- machine_exports("#{name}-machine"),
         # kitty: false — tmux wants its Ctrl+B prefix as legacy \x02, not CSI-u (see Terminal.init).
         {:ok, pid} <-
           safe_spawn_harness(:machine, exports, launcher: profile_launcher(world_id, name, profile), kitty: false) do
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

  # The bare `pi` invocation for a profile: config dir as PI_CODING_AGENT_DIR, persona as
  # --append-system-prompt, driver as --model. Shared by `profile_launcher` (the center's new-session)
  # and any windowed pi. The model MUST ride as a --model flag: pi resolves settings.json defaultModel
  # BEFORE pi-multi-account registers `anthropic`, so a claude-* default falls back to glm; the CLI
  # flag applies after extensions load, so it sticks (verified 2026-08-17).
  @doc false
  def pi_command(%Profile{} = profile) do
    base = Application.get_env(:aleph, :spawn_launcher, "mise exec -- pi")
    dir = Profiles.config_dir(profile.name)
    prompt = if profile.system_prompt, do: " --append-system-prompt #{Path.join(dir, "system_prompt.md")}", else: ""

    model =
      case profile.model do
        %{provider: prov, model: m, thinking: think} -> " --model #{prov}/#{m} --thinking #{think}"
        _ -> ""
      end

    "env PI_CODING_AGENT_DIR=#{dir} #{base}#{prompt}#{model}"
  end

  # The center coworker's launcher: pi on its OWN tmux server (`-L aleph-world-<id>`, id-derived —
  # not name-derived, so a world rename can't orphan it — + the profile's persistence-free
  # tmux.conf), window 0 named `lead_name` (the roster lead's name — the tab-strip label).
  # MANOS_RELOAD_CMD lets manos/reload respawn in place with --continue, keeping the thread across
  # the restart.
  def profile_launcher(world_id, lead_name, %Profile{} = profile) do
    pi = pi_command(profile)
    dir = Profiles.config_dir(profile.name)
    reload_cmd = {"MANOS_RELOAD_CMD", pi <> " --continue"}
    env_flags = Enum.map_join([reload_cmd], " ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)

    "tmux -L #{world_socket(world_id)} -f #{Path.join(dir, "tmux.conf")}" <>
      " new-session -A -s #{world_session(world_id)} -n #{lead_name} #{funes_identity_flags()} #{env_flags} '#{pi}'"
  end

  @doc false
  # `-e FUNES_X="$FUNES_X"` for each identity var. The Tlön pi's MCP wiring reads `${FUNES_MCP_URL}`
  # (profile mcp.json) and mints a bearer for FUNES_THREAD/FUNES_AUTHOR — but spawn_harness only
  # `export`s those in pi's ONE-SHOT launch shell, so they live in pi's PROCESS env alone. A
  # continuum/`--continue` restore, a `respawn-pane`, or a reload in a clean shell then boots with
  # `${FUNES_MCP_URL}` empty → the funes server never registers ("Tool not found", never the 404 the
  # adapter self-heals). Putting them in the tmux SESSION env via `-e` makes the identity durable
  # across respawns; `-e` also refreshes on `new-session -A`, so an aleph restart re-freshes a stale
  # identity instead of stranding it. bash sourced the exports first, so it expands the values here
  # into the current literal ones.
  def funes_identity_flags do
    Enum.map_join(@funes_identity_env, " ", fn var -> ~s(-e #{var}="$#{var}") end)
  end

  # POSIX single-quote: escape embedded quotes as '\'' so the value survives the shell verbatim.
  defp sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # A World's tmux session/socket, id-derived (rename-proof) — replaces the old singleton "tlon"
  # session on the lead-name-derived "aleph-<coworker>" socket. Two worlds can never collide on
  # either name, and a world rename can't orphan a running session.
  defp world_session(id), do: "w#{id}"
  defp world_socket(id), do: "aleph-world-#{id}"

  # A World's windows as tabs — aleph draws them itself (tmux's own status bar is off), so it asks
  # tmux for the live truth rather than tracking cockpit state (can't drift). Best-effort: the
  # session not being up yet is an empty strip, not a crash.
  defp tlon_tabs(world_id) do
    args = ["list-windows", "-t", world_session(world_id), "-F", "\#{window_active}\t\#{window_index}\t\#{window_name}"]

    case tlon_run(world_id, args) do
      {out, 0} -> parse_tlon_tabs(out)
      _ -> []
    end
  end

  # Every World tmux query/re-point call routes through here — one seam over the coworker's private
  # server (send-keys paths like inject_text/submit_turn still shell out directly) — so a test can
  # inject a fake runner (`:aleph, :tlon_cmd`) and assert argv without a live tmux.
  defp tlon_run(world_id, args) do
    runner = Application.get_env(:aleph, :tlon_cmd, &System.cmd/3)
    runner.("tmux", tlon_tmux(world_id, args), stderr_to_stdout: true)
  end

  # Every tmux call about a World's coworker targets ITS private server (`-L aleph-world-<id>`),
  # never the user's default one. Degrades to no `-L` flag if there's no active world id (funes-down
  # with the fallback World somehow also gone — never happens today: `Space.world_spaces/1` always
  # yields at least the sentinel).
  defp tlon_tmux(nil, args), do: args
  defp tlon_tmux(world_id, args), do: ["-L", world_socket(world_id)] ++ args

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
  # draws past the frame (a wider PTY spills; a shorter one leaves a dead band). Tlön's WindowBar
  # and Pulse bands already shrink that rect (they're their own sections, not the terminal's), so
  # no separate reserve is needed here.
  defp center_dims(%{active_key: active_key, w: w, h: h}) do
    rect = View.center_rect(active_key, w, h)
    {max(rect.w, 1), max(rect.h, 1)}
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
