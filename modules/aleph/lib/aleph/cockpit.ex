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
  alias Aleph.Harness
  alias Aleph.Keymap
  alias Aleph.LeafWindow
  alias Aleph.Mouse
  alias Aleph.Osc
  alias Aleph.Panel
  alias Aleph.Panel.Border
  alias Aleph.Panel.WindowBar
  alias Aleph.Profile
  alias Aleph.Profiles
  alias Aleph.Sessions
  alias Aleph.Space
  alias Aleph.Terminal
  alias Aleph.Tlon.Focus
  alias Aleph.View
  alias Aleph.WorldTemplates
  alias Funes.Bus
  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.MCP.Spawn
  alias Funes.Staff
  alias Funes.Worlds
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
    # Explicit thinking/idle declarations (funes:presence) — the "typing" indicator's rich half.
    Bus.subscribe_presence()
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
            # Orbis' focus toggle (`h`/`l`) — which cursor its j/k drives: the survey's per-row
            # cursor (default, so a fresh Orbis opens ready to zoom a world) or the thread list.
            orbis_focus: :survey,
            # The Orbis survey's per-row cursor (j/k), clamped to the live world count at keypress
            # time (Aleph.Keymap) — `Enter`/click resolve it to that row's world id.
            survey_cursor: 0,
            # Orbis' second face (D2.1): `:survey` (Chorus, the default) or `:author` (Panel.Author
            # — create/delete funes worlds). `a` toggles; Esc in `:author` steps back.
            orbis_face: :survey,
            # The author face's own per-row cursor (j/k), clamped to `Aleph.Worlds.all/0`'s length
            # at keypress time — mirrors `survey_cursor`.
            author_cursor: 0,
            # The author face's delete confirm arm (D2.5): the world id a `d` press armed, or nil.
            # A second `d` on this SAME id confirms; any other key cancels (Aleph.Keymap).
            pending_delete: nil,
            # Tlön nav's delete confirm arm: the `{kind, payload, label}` a `d` press resolved
            # (MEMORY fact / LEAVES leaf), or nil. Second `d` confirms; any other key cancels.
            tlon_delete: nil,
            # The field editor's own state (D2.4 Chunk 2a): `%{id, field, sub, mode}` while `e` has
            # opened it, else nil. VIEW cursors only — the world's data lives in funes and is
            # re-read from `Aleph.Worlds.all/0` every render (Aleph.Keymap).
            author_edit: nil,
            subscribed_thread: nil,
            leader_pending?: false,
            # LOCK mode (design 2026-08-23): Alt+g total-passthrough to the center — every other
            # key, Alt chords included, forwards raw so readline/emacs keep their bindings.
            lock?: false,
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
            # The WORKLINES pane's read (every open workline's stage/gate/blocking check), cached
            # with the other probes on the same @probe_ms throttle — Panel.Workline.
            worklines: nil,
            # The Leaves reorder context (the active WindowBar tab's agent), derived once per render
            # (View.focused_lead) — leaves_data/1 injects it for the render read AND yank/attach/
            # preview, so cursor indexing always matches the row order on screen.
            focused_lead: nil,
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
            opening_injected: MapSet.new(),
            # Threads already told "parked: leaf cap reached" — the note posts once, not per render.
            parked_noted: MapSet.new(),
            # Explicit thinking presence: thread_id => %{agent => started_at}. Seeded from the
            # store (reconcile-on-connect), then maintained by the funes:presence Bus events.
            thinking: thinking_snapshot(),
            # Transmitted kitty-graphics ids (design 2026-08-23 §Images) — the sync/2 cache so a
            # placement already on the tty isn't re-transmitted every frame.
            graphics: MapSet.new()
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
    # Every placed image's cell rect is now stale — clear the tty and the sync cache so the next
    # paint re-places (and re-transmits, since the cache is gone) at the new geometry.
    if Aleph.Graphics.kitty?(), do: IO.write(Aleph.Graphics.delete_all())
    {:noreply, render(%{state | graphics: MapSet.new()})}
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
    # `author_worlds` (D2.2): the author face's own world list, derived per keypress like
    # `composer_thread_id` — `Aleph.Worlds.all/0` is a cached GenServer call (no DB hit), so this
    # keeps `Aleph.Keymap` a pure reducer with no funes call of its own.
    keymap_state =
      %{state | flash: nil}
      |> Map.put(:center_live?, center_terminal(state) != nil)
      |> Map.put(:composer_thread_id, composer_thread_id(state))
      |> Map.put(:tlon_layout, tlon_layout(state))
      |> Map.put(:author_worlds, Aleph.Worlds.all())

    {next, effect} = Keymap.handle(key, keymap_state)

    next =
      reset_scrolls(state, Map.drop(next, [:center_live?, :composer_thread_id, :tlon_layout, :author_worlds]))

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
  # A hit on the carousel border's tab strip is checked FIRST — borders are chrome to
  # `Mouse.hit_panel/3` (never a click target), so the tab strip needs its own routing.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left, action: :press}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}

    case border_tab_hit(state.placements, x, y) do
      nil -> dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, state)
      idx -> {:noreply, render(%{state | right_pane_view: idx})}
    end
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
      teardown_closed_leaf(tag, row, state)
      state = if tag in @activity_tags, do: push_activity(state, tag, row), else: state
      {:noreply, render(state)}
    else
      {:noreply, state}
    end
  end

  # Workline stage machinery (slice 2): a GATE is the operator's — flash it; an advance is
  # ambient — just repaint so stage chips/counts stay live.
  def handle_info({:workline_gated, thread}, state) do
    desktop_notify(:workline_gated, thread)
    {:noreply, render(%{state | flash: "⏸ workline “#{thread.title}” parked at #{thread.stage} — approve #{thread.id}"})}
  end

  # Entering verify dispatches the DETERMINISTIC verifier (scripts/workline-verify.sh):
  # gates run + evidence recorded + advance-on-green, independent of the builder by
  # construction. Fire-and-forget — the script reports through funes, not this process.
  def handle_info({:workline_advanced, %{stage: "verify"} = thread}, state) do
    {:ok, _pid} =
      Task.start(fn ->
        System.cmd("mise", ["run", "workline:verify", "--", to_string(thread.id), thread.slug], stderr_to_stdout: true)
      end)

    {:noreply, render(%{state | flash: "▶ verifier dispatched for #{thread.slug}"})}
  end

  def handle_info({:workline_advanced, _thread}, state), do: {:noreply, render(state)}

  # Habit review events refresh the Habits panel (Tlön). No desktop notification — a proposed
  # habit is a quiet queue entry for review, not an interrupt.
  def handle_info({tag, _row}, state) when tag in [:habit_proposed, :habit_approved, :habit_rejected] do
    {:noreply, render(state)}
  end

  # Explicit presence: idempotent updates, so the double delivery on the focused thread
  # (funes:presence + its thread topic) just re-writes the same entry.
  def handle_info({:presence_thinking, %{thread_id: tid, agent: agent, started_at: at}}, state) do
    thinking = Map.update(state.thinking, tid, %{agent => at}, &Map.put(&1, agent, at))
    {:noreply, render(%{state | thinking: thinking})}
  end

  def handle_info({:presence_idle, %{thread_id: tid, agent: agent}}, state) do
    cleared = state.thinking |> Map.get(tid, %{}) |> Map.delete(agent)
    thinking = if cleared == %{}, do: Map.delete(state.thinking, tid), else: Map.put(state.thinking, tid, cleared)
    {:noreply, render(%{state | thinking: thinking})}
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

  # A closed leaf's window is torn down (the driver contract's `teardown`, Slice F): the seat
  # frees instead of idling forever — the warm-pool groundwork. Safe against the standing center:
  # `leaf_tab` only matches `@funes_thread`-tagged / legacy `t<id>` windows, never the lead's own
  # window. Can't respawn-loop: the spawn candidates (`Funes.staffed_machine_threads`) are OPEN
  # threads only. Best-effort — a vanished window is already what we wanted.
  defp teardown_closed_leaf(:thread_closed, %{scope: "machine", id: id}, state) when is_integer(id) do
    world_id = active_world_id(state)

    case leaf_tab(tlon_tabs(world_id), id) do
      %{index: index} -> tlon_run(world_id, ["kill-window", "-t", "#{world_session(world_id)}:#{index}"])
      _ -> :ok
    end

    :ok
  end

  defp teardown_closed_leaf(_tag, _row, _state), do: :ok

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
  #   * a worker-led staffed thread (claude OR pi — Slice A) that's live AND past its opening turn
  #     → route onto `t<id>`, so replies reach the session working THAT thread — not the standing
  #     coworker (otherwise both the `t2` session and the standing one would answer the same post).
  #   * a worker-led staffed thread mid-spawn / pre-opening → `:skip`: `ensure_thread_sessions`
  #     owns the opening turn (two-phase, race-safe); waking here would double it.
  #   * no staffed lead, or a meta/unknown lead (no leaf window for it) → route globally.
  defp delivery_target(%{thread_id: tid}, state, lead) when is_integer(tid) do
    standing = state.standing_thread_id || machine_thread_id()

    cond do
      tid == standing -> {:route, nil}
      is_nil(lead) or not leaf_staffed?(lead, active_world_id(state)) -> {:route, nil}
      window = staffed_leaf_window(tid, state) -> {:route, window}
      true -> :skip
    end
  end

  defp delivery_target(_row, _state, _lead), do: {:route, nil}

  # The live window NAME of a staffed thread's leaf session, once its opening turn has been
  # submitted — the `staffed_window` redirect target `Aleph.Mention.route/3` rewrites the lead
  # onto. Resolved via `leaf_tab` (the `@funes_thread` routing map — Slice C); the submitted
  # check reads the window's own `@funes_opening` tag first, so a restarted cockpit (empty
  # `opening_injected`) keeps delivering to already-running leaves instead of `:skip`ping them
  # forever. nil while mid-spawn / pre-opening (→ `:skip`; the spawn pass owns the opening turn).
  defp staffed_leaf_window(tid, state) do
    case leaf_tab(tlon_tabs(active_world_id(state)), tid) do
      %{name: name} = tab ->
        if tab[:opening] == "done" or MapSet.member?(state.opening_injected, tid), do: name

      _ ->
        nil
    end
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
      %Space{roster: [lead | _]} -> Profiles.roster_entry(lead).name
      _ -> nil
    end
  end

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
    _ = tlon_run(world_id, ["send-keys", "-l", "-t", "#{world_session(world_id)}:#{index}", text])
    :ok
  end

  # Send Enter to window `index` of world `world_id` — submits whatever's in its input. Split from
  # `inject_text` so a just-booted Claude Code TUI gets the text and the Enter as separate bursts (a
  # bundled Enter lands as a literal newline / gets swallowed, leaving the turn typed-but-unsent).
  defp submit_turn(world_id, index) do
    _ = tlon_run(world_id, ["send-keys", "-t", "#{world_session(world_id)}:#{index}", "Enter"])
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

  # A press on the carousel box's top frame row: which tab (Border.tab_at_x mirrors the drawn
  # runs)? Borders are chrome to hit_panel, so this runs before it.
  defp border_tab_hit(placements, x, y) do
    Enum.find_value(placements, fn
      {Border, %{tabs: tabs} = data, rect} when is_list(tabs) ->
        if y == rect.y and x >= rect.x and x < rect.x + rect.w, do: Border.tab_at_x(data, x - rect.x)

      _placement ->
        nil
    end)
  end

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

  # Enter on the Orbis survey (D0.2) — the same space-switch a click on the row runs.
  defp apply_effect({:switch_space, key}, state), do: apply_pick({:switch_space, key}, state)

  # `a` (or Esc from the author face) landed: flip Orbis' face and repaint (D2.1).
  defp apply_effect({:toggle_orbis_face}, state), do: {:noreply, render(toggle_orbis_face(state))}

  # The author face's `n` verb landed: register a world from the armed template + typed name.
  defp apply_effect({:register_world, template, name}, state),
    do: {:noreply, render(register_world!(state, template, name))}

  # `d` on the author face's cursor world landed: arm the two-key delete confirm.
  defp apply_effect({:arm_delete, id, name}, state),
    do: {:noreply, render(%{state | pending_delete: id, flash: "press d again to delete #{name}"})}

  # The second `d` (still armed on this id) landed: remove the world.
  defp apply_effect({:remove_world, id}, state), do: {:noreply, render(remove_world!(state, id))}

  # The field editor's h/l rings and paths/roster sub-list add/remove (D2.4 Chunk 2a) landed: apply
  # the attrs map immediately — no draft/commit step, matching Settings' per-change apply.
  defp apply_effect({:edit_world, id, attrs}, state), do: {:noreply, render(edit_world!(state, id, attrs))}

  # The roster sub-editor's Tab-armed knob landed on Enter/Space (D2.4 Chunk 2b, absorbs Settings):
  # apply it via Aleph.Config.
  defp apply_effect({:coworker_knob, name, knob}, state), do: {:noreply, render(apply_coworker_knob!(state, name, knob))}

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

  # `d` in Tlön nav landed: arm the two-key confirm on the focused pane's selection — a MEMORY
  # floor fact (forget) or a LEAVES leaf (window + thread). Anywhere else: flash the miss.
  defp apply_effect(:tlon_delete_arm, state) do
    case tlon_delete_target(state) do
      nil ->
        {:noreply, render(%{state | flash: "nothing deletable under the cursor"})}

      {_kind, _payload, label} = target ->
        {:noreply, render(%{state | tlon_delete: target, flash: "press d again to #{label}"})}
    end
  end

  # The second `d` (still armed) landed: execute against the ARM-TIME target.
  defp apply_effect({:tlon_delete, {:fact, fact, _label}}, state) do
    flash =
      case Dossier.forget_fact(fact) do
        {:ok, _} -> "forgot fact ##{fact.id}"
        _ -> "couldn't forget fact ##{fact.id}"
      end

    {:noreply, render(%{state | memory: nil, flash: flash})}
  rescue
    e -> {:noreply, render(%{state | flash: "forget failed: #{Exception.message(e)}"})}
  end

  defp apply_effect({:tlon_delete, {:leaf, id, _label}}, state) do
    {:noreply, render(delete_leaf!(state, id))}
  rescue
    e -> {:noreply, render(%{state | flash: "leaf delete failed: #{Exception.message(e)}"})}
  end

  # `y` landed: resolve the focused pane's semantic text, OSC-52 it to the host clipboard
  # (through the tty, so it works over SSH), and flash what was taken.
  defp apply_effect(:yank, state) do
    case yank_text(state) do
      {label, text} ->
        IO.write(Osc.copy(text))
        {:noreply, render(%{state | flash: "yanked #{label}"})}

      nil ->
        {:noreply, render(%{state | flash: "nothing to yank here"})}
    end
  end

  @doc false
  # The pure decision behind `[`/`]`: advance `right_pane_view` by `dir`, wrapped at the CAROUSEL's
  # length (Health is pinned, never cycled — clarity slice 2). No carousel (0/1-panel right column)
  # → no-op, guards div-by-zero. Public + exposed (like `attach_leaf/2`/`preview_focused/1`) so it's
  # testable without a live GenServer.
  def cycle_pane_view(%{active_key: key} = state, dir) when Space.world?(key) do
    case Space.fetch(key) do
      %Space{} = space ->
        case Space.carousel(space) do
          [] ->
            state

          carousel ->
            n = length(carousel)
            %{state | right_pane_view: rem(state.right_pane_view + dir + n, n)}
        end

      nil ->
        state
    end
  end

  def cycle_pane_view(state, _dir), do: state

  @doc false
  # The pure flip behind Orbis' `a`/Esc (D2.1) — public + exposed like `cycle_pane_view/2` so it's
  # testable without a live GenServer.
  def toggle_orbis_face(%{orbis_face: :author} = state), do: %{state | orbis_face: :survey}
  def toggle_orbis_face(state), do: %{state | orbis_face: :author}

  @doc false
  # Register a world from `template` + the operator-typed `name` (D2.3's `n` verb). `{:ok, _}`
  # clears the input and flashes; `{:error, changeset}` (a blank OR duplicate name — both are the
  # funes changeset's job, not re-validated here) flashes the reason and REOPENS the input with
  # what was typed, so a rejected name can be edited and resubmitted rather than retyped from
  # scratch. Wrapped like `create_thread`/`post_message` — a funes hiccup flashes, never crashes
  # the cockpit.
  def register_world!(state, template, name) do
    case Worlds.register(WorldTemplates.new_world_attrs(template, name)) do
      {:ok, world} ->
        %{state | input: nil, flash: "created #{world.name}"}

      {:error, changeset} ->
        %{
          state
          | input: %{kind: :new_world, buffer: name, cursor: String.length(name), template: template},
            flash: "couldn't create “#{name}” — #{changeset_error(changeset)}"
        }
    end
  rescue
    e -> %{state | flash: "create failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "create failed: #{inspect(reason)}"}
  end

  @doc false
  # Remove world `id` (D2.5's second `d`). Guards against stranding the cockpit on a deleted
  # active world (falls back to `:orbis`) and clamps `author_cursor` to the shrunk list. A missing
  # world (already gone) or a funes hiccup flashes, never crashes.
  def remove_world!(state, id) do
    case Worlds.get(id) do
      nil ->
        %{state | flash: "world ##{id} already gone"}

      world ->
        case Worlds.remove(world) do
          {:ok, _} ->
            state
            |> Map.put(:active_key, if(state.active_key == id, do: :orbis, else: state.active_key))
            |> Map.put(:author_cursor, clamp_author_cursor(state.author_cursor))
            |> Map.put(:flash, "deleted #{world.name}")

          {:error, changeset} ->
            %{state | flash: "couldn't delete #{world.name} — #{changeset_error(changeset)}"}
        end
    end
  rescue
    e -> %{state | flash: "delete failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "delete failed: #{inspect(reason)}"}
  end

  # Re-clamp the author cursor against the POST-delete count (one fewer row) — same edge-clamp
  # discipline as the keymap's move_author_cursor, applied here since a delete can shrink the list
  # out from under a cursor sitting on (or past) the new last row.
  defp clamp_author_cursor(cursor), do: max(min(cursor, max(length(Worlds.all()) - 1, 0)), 0)

  @doc false
  # Apply one field edit (D2.4 Chunk 2a: the editor's type/scope rings, and the paths/roster
  # sub-list's add/remove) immediately — no draft/commit step, mirroring how Settings applies each
  # change on the spot. `name` is immutable (`World.edit_changeset` drops it — see funes/world.ex);
  # nothing here special-cases it. Same missing/error/rescue shape as `register_world!`/
  # `remove_world!`. On success, re-clamps `author_edit.sub` against the POST-edit paths/roster
  # length (a removal can strand `sub` past the shrunk list, same reasoning as
  # `clamp_author_cursor/1` above).
  def edit_world!(state, id, attrs) do
    case Worlds.get(id) do
      nil ->
        %{state | flash: "world ##{id} already gone"}

      world ->
        case Worlds.edit(world, attrs) do
          {:ok, updated} -> reclamp_author_edit_sub(%{state | flash: "updated #{updated.name}"})
          {:error, changeset} -> %{state | flash: "couldn't update #{world.name} — #{changeset_error(changeset)}"}
        end
    end
  rescue
    e -> %{state | flash: "edit failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "edit failed: #{inspect(reason)}"}
  end

  # Only reachable when `author_edit` is actually mid-edit on a paths/roster sub-list (field 2/3) —
  # elsewhere (the type/scope rings, or no editor open) this is a no-op via the fallback clause.
  defp reclamp_author_edit_sub(%{author_edit: %{id: id, field: field} = edit} = state) when field in [2, 3] do
    case Worlds.get(id) do
      nil ->
        state

      world ->
        len = world |> Map.get(sub_list_field(field)) |> length()
        %{state | author_edit: %{edit | sub: edit.sub |> min(max(len - 1, 0)) |> max(0)}}
    end
  end

  defp reclamp_author_edit_sub(state), do: state

  defp sub_list_field(2), do: :paths
  defp sub_list_field(3), do: :roster

  @doc false
  # The roster sub-editor's Tab+Enter/Space knob (D2.4 Chunk 2b — absorbs the Settings modal):
  # cycle the sub-selected coworker's model ring, or flip its yolo policy, writing Aleph.Config
  # (file-backed, applies on the coworker's NEXT SPAWN — same honest scope as the `m` verb/old
  # Settings). Looks the roster entry up off the LIVE world (Worlds.get, like edit_world!) rather
  # than trust the effect's bare name, so the entry's archetype (the model ring's default-fallback
  # source) is available.
  def apply_coworker_knob!(state, name, knob) do
    case roster_entry_for(state, name) do
      nil -> %{state | flash: "#{name}: roster entry not found"}
      entry -> %{state | flash: apply_knob(entry, knob)}
    end
  rescue
    e -> %{state | flash: "settings write failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "settings write failed: #{inspect(reason)}"}
  end

  defp roster_entry_for(%{author_edit: %{id: id}}, name) do
    case Worlds.get(id) do
      nil -> nil
      world -> Enum.find(world.roster || [], &(&1["name"] == name))
    end
  end

  defp roster_entry_for(_state, _name), do: nil

  defp apply_knob(entry, :model) do
    norm = Profiles.roster_entry(entry)
    next = Profiles.next_model(Profiles.instantiate(norm).model)
    Aleph.Config.put_coworker_model(norm.name, next)
    "#{norm.name} driver → #{next.provider}/#{next.model} — applies on next spawn (aleph:reset)"
  end

  defp apply_knob(entry, :yolo) do
    name = entry["name"]
    next = Aleph.Config.coworker_yolo(name) != true
    Aleph.Config.put_coworker_yolo(name, next)
    policy = if next, do: "yolo (auto-approve)", else: "ask"
    "#{name} permissions → #{policy} — applies on next spawn (aleph:reset)"
  end

  # A short "field message, message" sentence from an Ecto changeset — surfaces e.g. a duplicate
  # name's UNIQUE(name) violation ("name has already been taken") without a full inspect dump.
  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

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

  # What `d` would delete under the current focus: a MEMORY floor fact (forget) or a LEAVES
  # leaf (its window + thread). The label rides along for the arm flash.
  defp tlon_delete_target(state) do
    cond do
      fact = selected_floor_fact(state) -> {:fact, fact, "forget fact ##{fact.id}"}
      leaf = selected_leaf(state) -> {:leaf, leaf.id, "delete leaf ##{leaf.id} (window + thread)"}
      true -> nil
    end
  end

  # The floor fact the focus points at — selected_habit's twin for the floor section (0).
  defp selected_floor_fact(
         %{active_key: key, memory: %{floor: floor}, focus: %{in_terminal?: false, section: 0} = focus} = state
       )
       when Space.world?(key) do
    layout = tlon_layout(state)
    if Focus.focused_pane(focus, layout) == Panel.Memory, do: Enum.at(floor, Focus.cursor(focus, layout))
  end

  defp selected_floor_fact(_state), do: nil

  # The leaf row under the Leaves cursor in nav — the same on-screen ordering attach/yank use.
  defp selected_leaf(%{focus: %{in_terminal?: false} = focus} = state) do
    layout = tlon_layout(state)

    with Panel.Leaves <- Focus.focused_pane(focus, layout),
         %{} = data <- leaves_data(state) do
      Panel.Leaves.row_at(data, Focus.cursor(focus, layout))
    else
      _ -> nil
    end
  end

  defp selected_leaf(_state), do: nil

  # Kill the leaf's live `t<id>` window (if any), then hard-delete its thread through the funes
  # facade — it refuses the root machine thread, which flashes instead of half-deleting.
  defp delete_leaf!(state, id) do
    world_id = active_world_id(state)

    case leaf_index(tlon_tabs(world_id), id) do
      nil -> :ok
      idx -> tlon_run(world_id, ["kill-window", "-t", "#{world_session(world_id)}:#{idx}"])
    end

    flash =
      case Funes.delete_thread(id) do
        {:ok, thread} -> "deleted leaf ##{id} — #{thread.title}"
        {:error, reason} -> "delete refused: #{inspect(reason)}"
      end

    %{state | leaves: nil, flash: flash}
  end

  # The Leaves data EXACTLY as the panel renders it: the cached rollup + the reorder context
  # (`focused_lead`, derived once per paint in render/1) + the attached wash. The SINGLE enrichment
  # the render read (`reads.orbis`) and the nav paths (yank/attach/preview via
  # `Panel.Leaves.row_at/2`) all consume — cursor indexing can never disagree with the paint.
  defp leaves_data(state) do
    case Map.get(state, :leaves) do
      nil ->
        nil

      leaves ->
        leaves
        |> Map.put(:focused_lead, Map.get(state, :focused_lead))
        |> Map.put(:attached, attached_leaf(Map.get(state, :focused_session)))
    end
  end

  defp attached_leaf({:leaf, id}), do: id
  defp attached_leaf(_focused_session), do: nil

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
    world_id = active_world_id(state)

    # row_at over leaves_data: the ON-SCREEN row order (focused lead floated), never the raw rollup.
    case Panel.Leaves.row_at(leaves_data(state), Focus.cursor(state.focus, layout)) do
      %{id: id, lead: lead} ->
        tabs = tlon_tabs(world_id)

        case {leaf_index(tabs, id), window_index(tabs, lead)} do
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

    with Panel.Leaves <- Focus.focused_pane(state.focus, layout),
         # row_at over leaves_data: the ON-SCREEN row order, same as attach/yank.
         %{lead: lead} <- Panel.Leaves.row_at(leaves_data(state), Focus.cursor(state.focus, layout)),
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
    machine = machine_read(state)
    roster = Staff.roster()
    # The Leaves reorder context, derived ONCE per paint and cached — leaves_data/1 hands the same
    # value to the render read below and to yank/attach/preview between paints.
    state = %{state | focused_lead: View.focused_lead(%{machine: machine, active_key: state.active_key, roster: roster})}

    reads = %{
      active_key: state.active_key,
      focused_id: focused && focused.id,
      focused_title: focused && focused.title,
      roster: roster,
      threads: threads,
      scope: focused && Funes.Board.in_scope(focused),
      chatter: (focused && Channel.recent_messages(focused, 30)) || [],
      worlds: if(state.active_key == :orbis, do: orbis_worlds(state), else: []),
      # The survey's focus + per-row cursor, so Chorus can wash the cursor row :selected — only
      # meaningful in Orbis (`right_pane_view`'s same "harmless elsewhere" idiom).
      orbis_focus: state.orbis_focus,
      survey_cursor: state.survey_cursor,
      # Orbis' author face (D2.1/D2.2): which center panel to render, and its own cursor.
      # Meaningless-but-harmless outside Orbis, same idiom as `right_pane_view`.
      orbis_face: state.orbis_face,
      author_cursor: state.author_cursor,
      # The field editor (D2.4 Chunk 2a): nil unless `e` opened it. Meaningless-but-harmless
      # outside Orbis' author face, same idiom as `right_pane_view`.
      author_edit: state.author_edit,
      terminal: terminal_read(state, focused),
      machine: machine,
      presence: presence_read(state, focused, machine),
      crew: crew_read(state, machine),
      stack: state.stack || @empty_stack,
      health: state.health,
      activity: state.activity,
      memory: if(Space.world?(state.active_key), do: state.memory),
      orbis: if(Space.world?(state.active_key), do: leaves_data(state)),
      worklines: if(Space.world?(state.active_key), do: state.worklines),
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
      flash: state.flash,
      leader_pending?: state.leader_pending?,
      # LOCK mode (design 2026-08-23) — the footer's loudest chip.
      lock?: state.lock?,
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

    state = sync_graphics(state, placements)

    %{state | placements: placements}
  end

  # The kitty-graphics pass (design 2026-08-23): after the cell paint, place/refresh every
  # panel-declared image. Non-kitty hosts skip it wholesale (panels showed placeholder runs).
  defp sync_graphics(state, placements) do
    if Aleph.Graphics.kitty?() do
      wanted = Enum.flat_map(placements, fn {panel, data, rect} -> Panel.images(panel, data, rect) end)
      {io, cache} = Aleph.Graphics.sync(wanted, state.graphics)
      if IO.iodata_length(io) > 0, do: IO.write(io)
      %{state | graphics: cache}
    else
      state
    end
  end

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The reconcile-on-connect read: whatever the store already holds when the cockpit boots
  # (declares made before this subscribe). Degrades to empty if the store isn't up.
  defp thinking_snapshot do
    Map.new(Funes.Presence.Thinking.thinking_all(), fn {tid, entries} ->
      {tid, Map.new(entries, &{&1.agent, &1.started_at})}
    end)
  catch
    :exit, _ -> %{}
  end

  # The focused thread's presence for Panel.Conversation: explicit thinking declarations plus the
  # tmux-activity floor. Precedence thinking > working — an agent that DECLARED never re-lists as
  # merely inferred-working; live/none render nothing.
  defp presence_read(_state, nil, _machine), do: %{thinking: [], working: []}

  defp presence_read(state, focused, machine) do
    declared = Map.get(state.thinking, focused.id, %{})
    names = declared |> Map.keys() |> Enum.sort()
    now = System.os_time(:second)
    thinking = Enum.map(names, &{&1, max(now - declared[&1], 0)})
    %{thinking: thinking, working: working_lead(machine, focused, names)}
  end

  defp working_lead(%{tabs: tabs}, focused, thinking) do
    with :working <- Aleph.Presence.thread_status(tabs, focused.id, System.os_time(:second)),
         lead when is_binary(lead) <- Funes.thread_lead(focused.id),
         false <- lead in thinking do
      [lead]
    else
      _ -> []
    end
  end

  defp working_lead(_machine, _focused, _thinking), do: []

  # The CREW sidebar's read: the active World's roster joined with the tmux snapshot, the leaf
  # leads, and the thinking declarations (Aleph.Panel.Crew.coworkers/6). Lead lookups go one
  # funes query per live leaf window — at most the leaf cap.
  defp crew_read(state, %{tabs: tabs}) do
    led_by =
      tabs
      |> Enum.filter(&is_integer(&1.thread_id))
      |> Enum.reduce(%{}, fn %{thread_id: tid}, acc ->
        case Funes.thread_lead(tid) do
          lead when is_binary(lead) -> Map.update(acc, lead, [tid], &[tid | &1])
          _ -> acc
        end
      end)

    titles = Map.new(state.threads, &{&1.id, &1.title})
    roster = active_roster(active_world_id(state))

    %{
      coworkers: Panel.Crew.coworkers(roster, tabs, led_by, titles, state.thinking, System.os_time(:second)),
      leaves: {Enum.count(tabs, &leaf_window?/1), Aleph.Config.max_leaves()}
    }
  end

  defp crew_read(_state, _machine), do: nil

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
          # Health pinned + carousel (clarity slice 2) — what's actually on screen, so the focus
          # SM's pane index can't point at a box View didn't draw.
          right: Space.visible_right(space, state.right_pane_view),
          sections: %{Panel.Memory => memory_sections(state)},
          counts: pane_counts(state)
        }
    end
  end

  defp tlon_layout(_state), do: %{left: [], right: [], sections: %{}, counts: %{}}

  # HABITS collapses when empty (Panel.Memory), so the Tab ring must shrink with it.
  defp memory_sections(%{memory: %{habits: habits}}) when habits != [], do: 2
  defp memory_sections(_state), do: 1

  defp space_at_cursor(state, layout), do: Enum.at(Space.all(), Focus.cursor(state.focus, layout)).key

  # The navigable item count per pane, for j/k clamping. Commits = the commit-log length; Memory is
  # sectioned — j/k walks the ACTIVE section's list (floor=0, habits=1), so its count follows
  # focus.section. Panes without a list are absent (0 → j/k is a no-op there).
  defp pane_counts(state) do
    %{
      Panel.Spaces => length(Space.all()),
      Panel.Stack => length((state.stack || @empty_stack).commits),
      Panel.Memory => memory_section_count(state),
      Panel.Leaves => leaf_count(state.leaves),
      Panel.Workline => worklines_count(state.worklines)
    }
  end

  defp leaf_count(%{rows: rows}), do: length(rows)
  defp leaf_count(_), do: 0

  defp worklines_count(%{worklines: worklines}), do: length(worklines)
  defp worklines_count(_), do: 0

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

  @doc false
  # The focused selection's clipboard text — pane dispatch mirrors tlon_detail/2. An open detail
  # wins (yank what's on screen). Exposed (like `attach_leaf/2`) as the pure decision behind
  # `apply_effect(:yank, ...)`, testable without the tty write.
  def yank_text(%{focus: %Focus{detail?: true}} = state) do
    case tlon_detail(state, tlon_layout(state)) do
      %{title: title, lines: lines} -> {"detail", Enum.map_join([{title, nil} | lines], "\n", fn {t, _} -> t end)}
      _ -> nil
    end
  end

  def yank_text(state) do
    layout = tlon_layout(state)
    cursor = Focus.cursor(state.focus, layout)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Stack -> Panel.Stack.yank(state.stack, cursor)
      Panel.Memory -> Panel.Memory.yank(memory_for_yank(state), cursor)
      # leaves_data, not the raw rollup: yank must copy the row render highlighted (float order).
      Panel.Leaves -> Panel.Leaves.yank(leaves_data(state), cursor)
      _ -> nil
    end
  end

  defp memory_for_yank(%{memory: nil}), do: nil
  defp memory_for_yank(%{memory: memory, focus: focus}), do: Map.put(memory, :section, focus.section)

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
      %{state | stack: nil, health: nil, memory: nil, leaves: nil, worklines: nil}
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
        worklines: worklines_read(),
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

  # The WORKLINES pane read: every open workline's stage/gate/blocking-check status.
  defp worklines_read do
    %{worklines: Funes.workline_statuses()}
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
          pid when is_pid(pid) ->
            # Harnesses inside the center can emit kitty graphics themselves — tmux must pass the
            # APC through instead of eating it (design 2026-08-23 §Images rider).
            _ = tlon_run(world_id, ["set-option", "-g", "allow-passthrough", "on"])
            capture_standing_thread_id(state)

          _ ->
            %{state | machine_retry_at: now + @machine_spawn_backoff_ms}
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
      |> Enum.map(&Profiles.roster_entry/1)
      |> Enum.reject(&MapSet.member?(existing, &1.name))
      |> Enum.each(fn %{archetype: arch, name: name} ->
        spawn_window(world_id, Profiles.instantiate(%{archetype: arch, name: name}))
      end)
    end

    state
  end

  # A tail window's launcher comes from its profile's HARNESS DRIVER (Slice D) — real Claude
  # (honestly identified, no pi-multi-account impersonation — see Aleph.Profiles' @seed_roster
  # comment) or a windowed pi; the spawn plumbing is shared. Materialised first: both drivers
  # read the profile's config dir (pi: the whole dir; claude: system_prompt.md as the role).
  defp spawn_window(world_id, %Profile{name: name} = profile) do
    _ = materialise_profile(profile)
    command = Harness.driver(profile.harness).launch_command(profile)
    spawn_harness_window(world_id, "#{name}-machine", name, machine_thread_id(), command)
  end

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
  # thread the operator opened outside the standing coworkers gets a live coworker
  # working IT specifically, not just accumulating unread messages. Two-phase, like the coworker
  # windows: `new-window` first (this pass), the opening turn only injected on a LATER render once
  # the window shows up live in `tlon_tabs()` — send-keys the instant `new-window` returns races
  # the harness's own boot and the first turn lands on the floor.
  #
  # EVERY worker roster lead gets a leaf window — claude AND pi harness, dispatched by the lead's
  # profile (per-thread-agents Slice A; the old `claude_launched?` gate left a pi lead's turns
  # landing in the ONE standing pi's context — the isolation bug). A meta (surveyor) or
  # roster-unknown lead gets none.
  #
  # Public seam (@doc false) so the suite drives the real dispatch through `:tlon_cmd`/`:tlon_join`
  # with injected `spaces`, mirroring `ensure_world_roster/2`.
  @doc false
  def ensure_thread_sessions(state, spaces \\ Space.all())

  def ensure_thread_sessions(%{active_key: key} = state, spaces) when Space.world?(key) do
    tabs = tlon_tabs(key)
    now = System.monotonic_time(:millisecond)
    roster = space_roster(key, spaces)
    threads = Funes.staffed_machine_threads()
    # Window names spawned THIS pass join the taken set, so two new leaves with the same title in
    # one render can't collide on a name (the tag targets by name once, right after new-window).
    taken = MapSet.new(tabs, & &1.name)
    # The leaf-cap budget (Config.max_leaves): seats left after the already-live leaves. A thread
    # past the cap stays open/staffed and just waits — a later pass staffs it once a seat frees.
    budget = Aleph.Config.max_leaves() - Enum.count(tabs, &leaf_window?/1)

    {state, _taken, _budget} =
      Enum.reduce(threads, {state, taken, budget}, fn thread, {st, tk, bg} ->
        ensure_thread_session(key, roster, thread, tabs, now, st, tk, bg)
      end)

    sweep_orphan_leaves(key, tabs, MapSet.new(threads, & &1.id))
    state
  end

  def ensure_thread_sessions(state, _spaces), do: state

  # Is this tab a LEAF session (vs the center/tail/console windows)? The `@funes_thread` tag, or
  # the legacy `t<id>` name.
  defp leaf_window?(%{thread_id: tid}) when is_integer(tid), do: true
  defp leaf_window?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)

  # Convergent teardown: a leaf window whose thread is no longer open+staffed — closed while
  # aleph was down, or wholesale-cleared — dies here, not only on the `:thread_closed` Bus event
  # the cockpit may never have seen. Matches ONLY leaf windows (the `@funes_thread` tag, or the
  # legacy `t<id>` name); the center/tail/console windows are never candidates. Runs off the same
  # tabs snapshot as the spawn pass, so a leaf spawned this pass (absent from the snapshot) can't
  # be swept.
  defp sweep_orphan_leaves(world_id, tabs, live_ids) do
    for tab <- tabs, orphan_leaf?(tab, live_ids) do
      tlon_run(world_id, ["kill-window", "-t", "#{world_session(world_id)}:#{tab.index}"])
    end

    :ok
  end

  defp orphan_leaf?(%{thread_id: tid}, live_ids) when is_integer(tid), do: not MapSet.member?(live_ids, tid)

  defp orphan_leaf?(%{name: name}, live_ids) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> not MapSet.member?(live_ids, String.to_integer(id))
      nil -> false
    end
  end

  defp ensure_thread_session(world_id, roster, %{id: id, lead: lead, title: title}, tabs, now, state, taken, budget) do
    cond do
      # The standing coworker's own thread — it already has a session (the center window),
      # just not a leaf one. Never spawn a duplicate for it.
      id == state.standing_thread_id ->
        {state, taken, budget}

      leaf_tab(tabs, id) ->
        {maybe_inject_opening_turn(world_id, id, tabs, now, state), taken, budget}

      not thread_spawn_due?(state.thread_spawn_retry[id], now) ->
        {state, taken, budget}

      budget <= 0 ->
        {note_parked(state, id), taken, budget}

      true ->
        spawn_leaf(world_id, roster, lead, title, id, now, state, taken, budget)
    end
  end

  # Tell the thread ONCE why nobody is working it yet — a silently parked leaf reads exactly like
  # the old silence bug. Best-effort; the note is informational, the parking is the budget check.
  defp note_parked(state, id) do
    if MapSet.member?(state.parked_noted, id) do
      state
    else
      _ =
        try do
          Channel.post(%{
            thread_id: id,
            author: "aleph",
            body:
              "⏸ parked — the leaf cap (#{Aleph.Config.max_leaves()}) is reached. This thread keeps its lead " <>
                "and starts automatically when a seat frees (close an idle leaf, or raise \"max_leaves\")."
          })
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

      %{state | parked_noted: MapSet.put(state.parked_noted, id)}
    end
  end

  # Spawn a leaf via the lead's roster profile: the harness DRIVER supplies the exec (Slice D),
  # the shared plumbing joins the leaf's OWN thread id so `FUNES_THREAD` binds the harness to the
  # thread it works. nil profile (meta/unknown lead) spawns nothing. The window gets a HUMAN name
  # (`<archetype>-<title-slug>`, Slice C); the routing key is the `@funes_thread` option
  # `tag_leaf/4` stamps right after the spawn.
  defp spawn_leaf(world_id, roster, lead, title, id, now, state, taken, budget) do
    case Profiles.leaf_profile(lead, roster) do
      nil ->
        {state, taken, budget}

      %Profile{} = profile ->
        _ = materialise_profile(profile)
        window = LeafWindow.name(profile.archetype, title, taken)
        command = Harness.driver(profile.harness).launch_command(profile)
        result = spawn_harness_window(world_id, lead, window, id, command)
        state = record_thread_spawn(tag_leaf(result, world_id, window, id), state, id, now)
        # A parked thread that finally got its seat may park again later; let it re-note then.
        state = %{state | parked_noted: MapSet.delete(state.parked_noted, id)}

        {state, MapSet.put(taken, window), budget - 1}
    end
  end

  # Stamp the routing key on a just-spawned leaf window: `@funes_thread <id>`. From here on the
  # window name is cosmetic — delivery/attach resolve thread → window via this option (`leaf_tab`).
  # Name-targeted exact-match (`=`); safe because the name was minted collision-free against this
  # pass's taken set. Only a successful spawn tags; a failed one just backs off.
  defp tag_leaf({_out, 0} = ok, world_id, window, id) do
    session = world_session(world_id)
    _ = tlon_run(world_id, ["set-option", "-w", "-t", "#{session}:=#{window}", "@funes_thread", "#{id}"])
    ok
  end

  defp tag_leaf(other, _world_id, _window, _id), do: other

  defp record_thread_spawn({_out, 0}, state, id, _now),
    do: %{state | thread_spawn_retry: Map.delete(state.thread_spawn_retry, id)}

  defp record_thread_spawn(_result, state, id, now),
    do: %{state | thread_spawn_retry: Map.put(state.thread_spawn_retry, id, now + @thread_spawn_backoff_ms)}

  # Is a per-thread session spawn attempt due? Mirrors `machine_spawn_due?/2` — nil means "no
  # backoff pending, try now".
  defp thread_spawn_due?(nil, _now), do: true
  defp thread_spawn_due?(retry_at, now), do: now >= retry_at

  # Does the cockpit staff a per-thread leaf window for this lead? Any WORKER roster handle
  # (claude or pi harness) qualifies — the predicate `delivery_target` and the spawn pass share,
  # so routing and spawning can never disagree about who owns a thread's turns.
  defp leaf_staffed?(lead, world_id), do: lead in Profiles.leaf_handles(active_roster(world_id))

  # This World's roster (`Aleph.Mention.route/3`'s resolution fixture) — funes-down / no roster
  # degrades to `[]` (nobody resolves, nobody wakes).
  defp active_roster(world_id) do
    case Space.fetch(world_id) do
      %Space{roster: roster} -> roster
      _ -> []
    end
  end

  # Same read against an injected spaces list (the `ensure_thread_sessions/2` test seam).
  defp space_roster(world_id, spaces) do
    case Space.fetch(world_id, spaces) do
      %Space{roster: roster} -> roster
      _ -> []
    end
  end

  # Two-phase, so a just-booted leaf window submits its opening turn instead of leaving it typed
  # but unsent: stage 1 types the text; stage 2, once the text has settled for
  # @opening_submit_delay_ms, sends Enter. The PHASE lives in tmux itself (`@funes_opening`
  # "typed"/"done" on the window) so a cockpit restart mid-phase can't re-type the opening into a
  # live session or (done-tagged) re-send it — process state only carries the settle timestamp; a
  # "typed" tag with no timestamp (restart) means the text settled long ago, submit now.
  defp maybe_inject_opening_turn(world_id, id, tabs, now, state) do
    tab = leaf_tab(tabs, id)

    cond do
      is_nil(tab) ->
        state

      tab.opening == "done" or MapSet.member?(state.opening_injected, id) ->
        mark_opening_done(state, id)

      tab.opening == "typed" or Map.has_key?(state.opening_text_at, id) ->
        submit_opening(world_id, id, tab, now, state)

      true ->
        inject_opening_text(world_id, id, tab)
        tag_opening(world_id, tab.index, "typed")
        %{state | opening_text_at: Map.put(state.opening_text_at, id, now)}
    end
  end

  defp submit_opening(world_id, id, tab, now, state) do
    typed_at = state.opening_text_at[id]

    if is_nil(typed_at) or now - typed_at >= @opening_submit_delay_ms do
      submit_turn(world_id, tab.index)
      tag_opening(world_id, tab.index, "done")
      mark_opening_done(state, id)
    else
      state
    end
  end

  defp mark_opening_done(state, id) do
    %{
      state
      | opening_injected: MapSet.put(state.opening_injected, id),
        opening_text_at: Map.delete(state.opening_text_at, id)
    }
  end

  # Stamp the opening phase on the window itself — index-targeted, best-effort.
  defp tag_opening(world_id, index, phase) do
    _ = tlon_run(world_id, ["set-option", "-w", "-t", "#{world_session(world_id)}:#{index}", "@funes_opening", phase])
    :ok
  end

  # Type the thread's latest operator message into its just-appeared leaf window (no Enter yet —
  # stage 2 submits). Best-effort: a thread with no operator message yet is silently skipped —
  # never a render crash.
  defp inject_opening_text(world_id, id, %{index: index}) do
    message = Funes.latest_operator_message(id)

    if message do
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

  # Open a harness window named `window` on `thread_id` as funes handle `handle`, running
  # `command` (the profile's `Aleph.Harness.Driver.launch_command/1`) in world `world_id`. The
  # roster tail windows AND the per-thread leaf windows all ride this ONE spawn: identity join +
  # tmux plumbing are harness-agnostic (Slice D); only the exec differs, and that came from the
  # driver. `FUNES_THREAD` binds the harness to the thread it's actually meant to work on.
  defp spawn_harness_window(world_id, handle, window, thread_id, command) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, handle, mandate: "machine") do
      script = "export TERM=xterm-256color\n" <> exports <> "\nexec " <> command
      # `-d`: spawn the window in the background — a coworker starting must NOT yank the operator
      # off whatever window they're on.
      tlon_run(world_id, ["new-window", "-d", "-t", world_session(world_id), "-n", window, script])
    end
  end

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
    %{archetype: arch, name: name} = Profiles.roster_entry(lead)

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

  # The bare `pi` invocation for a profile — moved to the pi harness driver (Slice D); kept as a
  # delegator for `profile_launcher` (the center's new-session) and `Aleph.Crew`.
  @doc false
  def pi_command(%Profile{} = profile), do: Harness.Pi.launch_command(profile)

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
    args = [
      "list-windows",
      "-t",
      world_session(world_id),
      "-F",
      "\#{window_active}\t\#{window_index}\t\#{window_name}\t\#{@funes_thread}\t\#{@funes_opening}\t\#{window_activity}"
    ]

    case tlon_run(world_id, args) do
      {out, 0} -> parse_tlon_tabs(out)
      _ -> []
    end
  end

  # Every World tmux call — queries, re-points, AND the send-keys injects — routes through here:
  # one seam over the coworker's private server, so a test can inject a fake runner
  # (`:aleph, :tlon_cmd`) and assert argv without a live tmux.
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
  # `<active>\t<index>\t<name>\t<@funes_thread>\t<@funes_opening>\t<window_activity>` — the index
  # is tmux's window index (select-window on a tab click); `@funes_thread` is the leaf routing key
  # stamped at spawn (Slice C — empty for non-leaf windows, parsed to nil); `@funes_opening` is the
  # two-phase opening-turn state ("typed"/"done") persisted in tmux so a cockpit restart never
  # re-types a live leaf's opening; `window_activity` is the last-content-change unix timestamp
  # `Aleph.Presence` infers "working" from. Shorter lines (older fakes/format) still parse,
  # missing fields nil.
  def parse_tlon_tabs(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 6) do
        [active, index, name | rest] when rest != [] or name != "" ->
          [thread, opening, activity] =
            case rest do
              [t, o, a] -> [t, o, a]
              [t, o] -> [t, o, ""]
              [t] -> [t, "", ""]
              [] -> ["", "", ""]
            end

          [
            %{
              name: name,
              active?: active == "1",
              index: index,
              thread_id: int_or_nil(thread),
              opening: if(opening in ["typed", "done"], do: opening),
              activity: int_or_nil(activity)
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp int_or_nil(s) do
    case Integer.parse(s) do
      {id, ""} -> id
      _ -> nil
    end
  end

  # The tab running thread `id`'s leaf session: the `@funes_thread`-stamped window (Slice C), else
  # the legacy `t<id>`-named one (a live pre-C window) — nil when the leaf has no window yet.
  # Routing resolves thread → window HERE, never by parsing a (now human-named) window name.
  defp leaf_tab(tabs, id), do: Enum.find(tabs, &(&1.thread_id == id)) || Enum.find(tabs, &(&1.name == "t#{id}"))

  defp leaf_index(tabs, id) do
    case leaf_tab(tabs, id) do
      %{index: index} -> index
      _ -> nil
    end
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
    # Best-effort: clear any placed images before the alt screen goes away. Straight to /dev/tty
    # like the Kitty pop below (the io server may already be winding down on a crash), and a
    # failure here must never skip the tty restore (a wedged shell is worse than a stray image).
    try do
      if Aleph.Graphics.kitty?(), do: File.write("/dev/tty", Aleph.Graphics.delete_all())
    catch
      _, _ -> :ok
    end

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
