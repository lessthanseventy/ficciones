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

  @doc "Resize the emulator AND the PTY (SIGWINCH to the child)."
  def resize(term, cols, rows), do: GenServer.call(term, {:resize, cols, rows})

  @doc "Scroll the scrollback by `delta` rows (negative = up into history)."
  def scroll(term, delta), do: GenServer.call(term, {:scroll, delta})

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

  def handle_call({:key, event}, _from, state) do
    case Terminal.input_key(state.term, event) do
      {:ok, bytes} -> PTY.write(state.pty, bytes)
      :none -> :ok
    end

    {:reply, :ok, state}
  end

  def handle_call({:resize, cols, rows}, _from, state) do
    Terminal.resize(state.term, cols, rows)
    PTY.resize(state.pty, cols, rows)
    {:reply, :ok, %{state | cols: cols, rows: rows}}
  end

  defp notify(%{notify: pid}, msg) when is_pid(pid), do: send(pid, {__MODULE__, self(), msg})
  defp notify(_state, _msg), do: :ok
end
