defmodule Aleph.Terminal do
  @moduledoc """
  One live session as a REAL embedded terminal (design §4, replacing the laggy capture-pane view).
  A GenServer that owns a `Ghostty.PTY` (a true `forkpty` running the harness — pi/claude get a
  real TTY) and a `Ghostty.Terminal` (Ghostty's own VT engine). It pumps the PTY's output into the
  emulator as it arrives, so the screen is live at native latency — no 500ms capture tick, no
  `send-keys` subprocess per key.

  The seams the cockpit uses:
    * `render_state/1` — the one-call renderer feed: `%{cells, cursor, foreground, background, …}`.
      `cells` is `[[{grapheme, fg, bg, flags}]]` (RGB) to blit; `cursor` carries the block/bar
      position + visibility so the embedded terminal shows a REAL cursor where you type.
    * `cells/1` — just the grid (a convenience over `render_state`).
    * `send_key/2` — a `Ghostty.KeyEvent` is encoded by the emulator (`input_key`) and written
      straight to the PTY: one native keystroke, not a shell-out.
    * `resize/3` — resize both the emulator and the PTY (SIGWINCH to the child; the VT reflows).

  Correctness: the emulator emits `{:pty_write, bytes}` — responses to queries a TUI sends (device
  attributes, cursor-position reports) — which we MUST write back to the PTY or a querying program
  hangs. `:bell` and `:title_changed` are forwarded to `:notify` so the cockpit can react.

  (`snapshot/2` — the plain-text/HTML briefing surface, §3b/§7 — is deferred: the `nif_snapshot`
  binary in ghostty 0.5.0 raises `formatter_creation_failed` here. `cells`/`render_state` render.)

  On new output it pings `:notify` with `{Aleph.Terminal, pid, :updated}` so the cockpit repaints
  exactly when the screen changed; `{:exited, status}` when the child ends. A dedicated, long-lived
  terminal per session (not a pool — a session's screen is its own and continuous).
  """
  use GenServer

  alias Ghostty.MouseEvent
  alias Ghostty.PTY
  alias Ghostty.Terminal

  @default_cols 80
  @default_rows 24
  # Theme options passed straight to Ghostty.Terminal so the embedded screen matches aleph.
  @theme_opts [:foreground, :background, :cursor_color, :palette, :max_scrollback]

  @doc """
  Start a session terminal. Opts: `:cmd` + `:args` (the harness command; default the login shell),
  `:cols`/`:rows` (default 80x24), `:notify` (a pid pinged on screen change / bell / title / exit),
  `:name`, plus theme passthroughs (`:foreground`, `:background`, `:cursor_color`, `:palette`,
  `:max_scrollback`) — RGB tuples matching the cockpit's palette.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "The full render feed: `%{cells, cursor, foreground, background, mouse, scrollbar, …}`."
  def render_state(term), do: GenServer.call(term, :render_state)

  @doc "The screen as a grid of `{grapheme, fg, bg, flags}` cells."
  def cells(term), do: GenServer.call(term, :cells)

  @doc "Encode a key event and write it to the PTY — a native keystroke."
  def send_key(term, %Ghostty.KeyEvent{} = event), do: GenServer.call(term, {:key, event})

  @doc "Write raw bytes straight to the PTY (a wake prompt, a paste) — no key encoding."
  def feed(term, bytes), do: GenServer.call(term, {:feed, bytes})

  @doc "Resize the emulator AND the PTY (SIGWINCH to the child)."
  def resize(term, cols, rows), do: GenServer.call(term, {:resize, cols, rows})

  @doc "Scroll the scrollback by `delta` rows (negative = up into history)."
  def scroll(term, delta), do: GenServer.call(term, {:scroll, delta})

  @doc "The embedded program's mouse-tracking modes (`%{tracking, x10, normal, button, any, sgr}`)."
  def mouse_modes(term), do: GenServer.call(term, :mouse_modes)

  @doc """
  The mouse wheel over the embedded terminal — the one input the cockpit routes here when the
  wheel is over the center region. It branches on whether the running program asked for mouse
  tracking (DEC `?1000`/`?1002`/`?1003`/`?9`):

    * tracking ON  — the wheel is forwarded as a button-4 (up) / button-5 (down) *press* to the
      PTY via `Ghostty.Terminal.input_mouse/2`, exactly like `send_key/2` but for the mouse. A
      mouse-aware TUI (vim/tmux/less in mouse mode) then scrolls its own view.
    * tracking OFF — the VT scrollback is scrolled `n` rows (up = into history, down = newer), so
      a plain shell or an unfocused TUI still scrolls its captured output.

  `x`/`y` are 0-indexed terminal-local cell coordinates (only used when forwarding). Returns
  `:forwarded` or `:scrolled` so the cockpit repaints only when the viewport moved (a forward
  surfaces as PTY output → an `:updated` ping → its own repaint; a scroll changes no PTY bytes).
  """
  def wheel(term, direction, n, x, y), do: GenServer.call(term, {:wheel, direction, n, x, y})

  @impl true
  def init(opts) do
    cols = opts[:cols] || @default_cols
    rows = opts[:rows] || @default_rows
    cmd = opts[:cmd] || System.get_env("SHELL") || "/bin/bash"
    args = opts[:args] || []

    term_opts = [cols: cols, rows: rows] ++ Keyword.take(opts, @theme_opts)
    {:ok, term} = Terminal.start_link(term_opts)
    {:ok, pty} = PTY.start_link(cmd: cmd, args: args, cols: cols, rows: rows)

    {:ok, %{term: term, pty: pty, notify: opts[:notify], cols: cols, rows: rows}}
  end

  # PTY output → the emulator, then tell the cockpit the screen moved.
  @impl true
  def handle_info({:data, bytes}, state) do
    Terminal.write(state.term, bytes)
    notify(state, :updated)
    {:noreply, state}
  end

  # A query response FROM the emulator: it must go back to the child, or a TUI that asked (device
  # attributes, cursor position) waits forever.
  def handle_info({:pty_write, bytes}, state) do
    PTY.write(state.pty, bytes)
    {:noreply, state}
  end

  def handle_info(:bell, state) do
    notify(state, :bell)
    {:noreply, state}
  end

  def handle_info(:title_changed, state) do
    notify(state, :title_changed)
    {:noreply, state}
  end

  def handle_info({:exit, status}, state) do
    notify(state, {:exited, status})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:render_state, _from, state), do: {:reply, Terminal.render_state(state.term), state}

  def handle_call(:cells, _from, state), do: {:reply, Terminal.cells(state.term), state}

  def handle_call({:scroll, delta}, _from, state) do
    Terminal.scroll(state.term, delta)
    {:reply, :ok, state}
  end

  def handle_call(:mouse_modes, _from, state), do: {:reply, Terminal.mouse_modes(state.term), state}

  # The wheel forward-vs-scroll branch (design: keep the Ghostty/mouse detail here, not the cockpit).
  # Dispatched on whether the embedded program enabled mouse tracking — a runtime boolean read
  # through a 1-arg helper so the two branches land on their own function heads (house rule).
  def handle_call({:wheel, direction, n, x, y}, _from, state) do
    {:reply, route_wheel(Terminal.mouse_modes(state.term).tracking, direction, n, x, y, state), state}
  end

  def handle_call({:key, event}, _from, state) do
    emit(state.pty, Terminal.input_key(state.term, event))
    {:reply, :ok, state}
  end

  def handle_call({:feed, bytes}, _from, state) do
    PTY.write(state.pty, bytes)
    {:reply, :ok, state}
  end

  # Already at this size — a no-op, so the cockpit can call resize every tick to self-correct a
  # freshly-spawned PTY without spamming the child with redundant SIGWINCHs (which make a TUI repaint).
  def handle_call({:resize, cols, rows}, _from, %{cols: cols, rows: rows} = state), do: {:reply, :ok, state}

  def handle_call({:resize, cols, rows}, _from, state) do
    Terminal.resize(state.term, cols, rows)
    PTY.resize(state.pty, cols, rows)
    {:reply, :ok, %{state | cols: cols, rows: rows}}
  end

  # --- the wheel forward-vs-scroll branch (design: keep the Ghostty/mouse detail here, not the cockpit) ---

  # Dispatched on whether the embedded program enabled mouse tracking — a runtime boolean read
  # through a 1-arg helper so the two branches land on their own function heads (house rule).
  defp route_wheel(tracking?, direction, n, x, y, state),
    do: route_wheel(tracking?, direction, n, x, y, state.term, state.pty)

  # tracking ON → forward a button-4/5 press to the PTY, exactly like `send_key/2` but for the mouse.
  defp route_wheel(true, direction, _n, x, y, term, pty) do
    event = %MouseEvent{action: :press, button: wheel_button(direction), mods: [], x: x * 1.0, y: y * 1.0}
    emit(pty, Terminal.input_mouse(term, event))
    :forwarded
  end

  # tracking OFF → scroll the VT scrollback (up = into history, down = newer). No PTY bytes, so the
  # cockpit repaints on the returned :scrolled.
  defp route_wheel(false, direction, n, _x, _y, term, _pty) do
    Terminal.scroll(term, scroll_delta(direction, n))
    :scrolled
  end

  # Write an encoder result to the PTY, or drop a :none (no sequence for this key/mouse under the
  # active modes). Shared by `:key` and `:wheel` — function-head dispatch, no two-arm `case`.
  defp emit(pty, {:ok, bytes}), do: PTY.write(pty, bytes)
  defp emit(_pty, :none), do: :ok

  @doc false
  # xterm mouse convention: button 4 = wheel up, button 5 = wheel down (Ghostty.MouseEvent maps
  # :four→4 / :five→5). Reported as a :press; the encoder applies the active mode's formatting.
  def wheel_button(:up), do: :four
  def wheel_button(:down), do: :five

  @doc false
  # Ghostty.Terminal.scroll: positive = down (newer), negative = up (into scrollback history).
  def scroll_delta(:up, n), do: -n
  def scroll_delta(:down, n), do: n

  defp notify(%{notify: pid}, msg) when is_pid(pid), do: send(pid, {__MODULE__, self(), msg})
  defp notify(_state, _msg), do: :ok
end
