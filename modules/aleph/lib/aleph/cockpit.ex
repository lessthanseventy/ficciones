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
  @tb_output_truecolor 5
  # TB_INPUT_ESC (1) | TB_INPUT_MOUSE (4) = 5 (termbox2.h §309–313): keep ESC-sequence parsing AND
  # emit mouse events, which the Driver translates into Event{type: :mouse, data: %{x, y, button}}.
  @tb_input_esc_mouse 5

  # The standing Tlön machine coworker's funes agent name — a stable, distinct identity so restarts
  # reuse the same agent and it never collides with a project thread's harness.
  @machine_agent "pi-machine"

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
        :termbox2_nif.tb_set_input_mode(@tb_input_esc_mouse)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())
        # Watch every session terminal — the `s` verb AND the arbiter's autonomous spawn repaint
        # through this cockpit, whoever started them.
        Sessions.observe(self())

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
            flash: nil,
            scrolls: %{},
            placements: []
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
    state = %{state | w: max(w, 1), h: max(h, 1)}
    resize_focused_terminal(state)
    {:noreply, render(state)}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    # Any keypress clears a prior flash (a spawn/create result), so it shows until you act again.
    {next, effect} = Keymap.handle(key, %{state | flash: nil})
    # A context switch (space or focused-thread change) resets the panels whose content swaps, so a
    # new thread's dossier/chat don't inherit the old one's scroll position. (Function-head dispatch
    # on what changed — house rule.)
    next = reset_scrolls(state, next)
    apply_effect(effect, next)
  end

  # A wheel routes to whatever panel is under the cursor: the center terminal forwards to its PTY
  # or scrolls its scrollback (Aleph.Terminal.wheel/5), a scrollable list panel advances its offset
  # (clamped to its content height), anything else is ignored.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: x, y: y, button: b}}}, state)
      when b in [:wheel_up, :wheel_down], do: dispatch_wheel(Mouse.hit_panel(state.placements, x, y), b, x, y, state)

  # A left click routes to the panel under the cursor and asks it what that row selects — focus a
  # thread, switch a space — then repaints. Non-selectable panels (Dossier/Stack/Tools, the center
  # terminal) return nil and the click is a no-op.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: x, y: y, button: :left}}}, state),
    do: dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, state)

  # Any other mouse event (right/middle button, motion) is not handled yet.
  def handle_cast({:dispatch, %Event{type: :mouse}}, state), do: {:noreply, state}

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
    # SIGWINCH) self-corrects within a tick instead of leaving the layout stranded at the old size.
    state = refresh_size(state)
    # And re-fit the center PTY to the center region — a terminal spawned *between* window resizes
    # (a new session, the Tlön coworker) starts at 80x24 and would otherwise fill only part of the
    # panel until the next resize. `Terminal.resize` is a no-op when the size is unchanged, so this
    # only actually reflows the child when it needs to.
    resize_focused_terminal(state)
    {:noreply, render(state)}
  end

  # An embedded session terminal moved (new output, bell, or the child exited) → repaint exactly
  # then, at native latency. This is why the center is smooth: it draws when the screen changed,
  # not on a timer.
  def handle_info({Terminal, _pid, _event}, state), do: {:noreply, render(state)}

  def handle_info(_msg, state), do: {:noreply, state}

  defp refresh_size(state) do
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # --- mouse routing (the Cockpit interprets Aleph.Mouse's pure decisions) ---

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
    do: scroll_wheel(scrollable?(data), panel, data, rect, b, state)

  defp scroll_wheel(true, panel, data, rect, b, state) do
    {dir, n} = Mouse.wheel_of(b)
    content_h = Panel.content_height(panel, data, rect.w)
    next = Mouse.clamp_offset((state.scrolls[panel] || 0) + scroll_delta(dir, n), content_h, rect.h)
    {:noreply, render(%{state | scrolls: Map.put(state.scrolls, panel, next)})}
  end

  defp scroll_wheel(false, _panel, _data, _rect, _b, state), do: {:noreply, state}

  defp scrollable?(data), do: is_map(data) and Map.has_key?(data, :scroll)

  defp scroll_delta(:up, n), do: -n
  defp scroll_delta(:down, n), do: n

  defp clamp_cell(v, extent), do: v |> max(0) |> min(max(extent - 1, 0))

  defp repaint_on_scroll(:scrolled, state), do: {:noreply, render(state)}
  defp repaint_on_scroll(:forwarded, state), do: {:noreply, state}

  defp dispatch_click(nil, _x, _y, state), do: {:noreply, state}

  # Clicking the center terminal focuses it — Enter's mouse analogue — so Ctrl+C/Esc reach the
  # child, not aleph (the Keymap forwards every key while focused; Ctrl+B still releases). Only when
  # there's a live session to type into; a click on the placeholder does nothing.
  defp dispatch_click({Panel.Terminal, _data, _rect}, _x, _y, state), do: focus_center(center_terminal(state), state)

  defp dispatch_click({panel, data, rect}, _x, y, state), do: apply_pick(Panel.pick(panel, data, rect, y - rect.y), state)

  defp focus_center(nil, state), do: {:noreply, state}

  defp focus_center(term, state) when is_pid(term), do: {:noreply, render(%{state | center_focused?: true, flash: nil})}

  defp apply_pick(nil, state), do: {:noreply, state}

  # Selecting a thread by click releases center focus — the focused terminal just changed, so
  # holding focus on the old one would misdirect the next keypress.
  defp apply_pick({:focus_thread, id}, state) do
    next = reset_scrolls(state, %{state | focused_id: id, center_focused?: false, flash: nil})
    {:noreply, render(next)}
  end

  defp apply_pick({:switch_space, key}, state) do
    next = reset_scrolls(state, %{state | active_key: key, center_focused?: false, flash: nil})
    {:noreply, render(next)}
  end

  # Reset scroll offsets when the context they're relative to changes. A space switch swaps every
  # panel, so all offsets go; a focus change only swaps the thread-specific panels (Dossier,
  # Conversation), so just those. Function-head dispatch on what changed — house rule.
  defp reset_scrolls(%{active_key: a}, %{active_key: a2} = next) when a != a2, do: %{next | scrolls: %{}}

  defp reset_scrolls(%{focused_id: f}, %{focused_id: f2} = next) when f != f2,
    do: %{next | scrolls: Map.drop(next.scrolls, [Panel.Dossier, Panel.Conversation])}

  defp reset_scrolls(_prev, next), do: next

  # --- interpret the reducer's effect (`Aleph.Keymap`) ---

  # State transitions live in the pure `Aleph.Keymap`; the Cockpit only runs the side effect it
  # asks for — repaint, quit, or forward a key to the focused tmux pane.
  defp apply_effect(:repaint, state), do: {:noreply, render(state)}
  # --- render ---
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

  # The `s` verb landed: spawn a session onto the focused thread. The result flashes in the footer.
  defp apply_effect({:spawn, thread_id}, state) do
    {:noreply, render(%{state | flash: spawn_onto(thread_id, state)})}
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
          {:ok, _pid} -> "session live — Enter to focus, Ctrl+B to release"
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
  def ghostty_key(%{key: :char, char: c} = ev), do: %KeyEvent{key: char_key(c), utf8: c, mods: mods(ev)}
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

  defp mods(ev) do
    [{:ctrl, ev[:ctrl]}, {:alt, ev[:alt]}, {:shift, ev[:shift]}]
    |> Enum.filter(fn {_mod, on?} -> on? end)
    |> Enum.map(fn {mod, _} -> mod end)
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
      stack: stack_read(state.active_key),
      scrolls: state.scrolls,
      input: state.input,
      flash: state.flash
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

  # The center is a live embedded terminal, only in the Sessions space. The focused thread's
  # Aleph.Terminal render_state (Ghostty's live cells + cursor) is read fresh; no session → the
  # placeholder. `:no_session` elsewhere so the panel isn't shown.
  defp terminal_read(%{active_key: key} = state, _focused) when key in [:sessions, :tlon] do
    state |> center_terminal() |> render_state_of()
  end

  defp terminal_read(_state, _focused), do: :no_session

  defp render_state_of(nil), do: :no_session
  defp render_state_of(term), do: Terminal.render_state(term)

  # The terminal the center shows, by space: Sessions → the focused thread's session; Tlön → a
  # machine shell at the repo root (working ON the env, not a project). nil elsewhere.
  defp center_terminal(%{active_key: :sessions} = state), do: state |> focused() |> terminal_for()
  defp center_terminal(%{active_key: :tlon}), do: machine_terminal()
  defp center_terminal(_state), do: nil

  defp terminal_for(nil), do: nil
  defp terminal_for(%{id: id}), do: Sessions.terminal(id)

  # The STACK/TOOLS reads are only gathered on Tlön (git log + version probes are wasted elsewhere).
  defp stack_read(:tlon), do: %{commits: Aleph.Stack.commits(), tools: Aleph.Stack.tools()}
  defp stack_read(_key), do: %{commits: [], tools: []}

  # The Tlön machine coworker — a pi session working ON the box, a funes citizen on a persistent
  # "machine" thread so its work (issues it files, checks it runs) is remembered and triageable.
  # pi (not claude) by design: Tlön is meta/triage/machine work, the flat-bucket workhorse — claude
  # stays the deliberate escalation for implementing code (AGENTS.md routing). Spawned once on first
  # Tlön entry and reused (keyed `:machine`, decoupled from the funes thread id); the fast path is a
  # bare registry lookup on every render.
  defp machine_terminal do
    case Sessions.terminal(:machine) do
      pid when is_pid(pid) -> pid
      nil -> spawn_machine_coworker()
    end
  end

  defp spawn_machine_coworker do
    with {:ok, %{exports: exports}} <- Spawn.env("Tlön", @machine_agent, mandate: "machine"),
         {:ok, pid} <- Sessions.spawn_harness(:machine, exports) do
      pid
    else
      _error -> nil
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
