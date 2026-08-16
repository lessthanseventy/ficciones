defmodule Aleph.Terminal do
  @moduledoc """
  One live session as a REAL embedded terminal (design §4, replacing the laggy capture-pane view).
  A GenServer that owns a `Ghostty.PTY` (a true `forkpty` running the harness — pi/claude get a
  real TTY) and a `Ghostty.Terminal` (Ghostty's own VT engine). It pumps the PTY's output into the
  emulator as it arrives, so the screen is live at native latency — no 500ms capture tick, no
  `send-keys` subprocess per key.

  The seams the cockpit uses:
    * `cells/1` — the current screen as `[[{grapheme, fg, bg, flags}]]` (RGB), to blit into the
      center region.
    * `send_key/2` — a `Ghostty.KeyEvent` is encoded by the emulator (`input_key`) and written
      straight to the PTY: one native keystroke, not a shell-out.
    * `resize/3` — resize both the emulator and the PTY (SIGWINCH to the child).

  (`snapshot/2` — the plain-text/HTML briefing surface, §3b/§7 — is deferred: the `nif_snapshot`
  binary in ghostty 0.5.0 raises `formatter_creation_failed` here. `cells/1` is enough to render,
  and briefing can reconstruct text from the grid until the NIF is fixed.)

  On new output it pings `:notify` with `{Aleph.Terminal, pid, :updated}` so the cockpit repaints
  exactly when the screen changed; `{:exited, status}` when the child ends. A dedicated, long-lived
  terminal per session (not a pool — a session's screen is its own and continuous).
  """
  use GenServer

  alias Ghostty.PTY
  alias Ghostty.Terminal

  @default_cols 80
  @default_rows 24

  @doc """
  Start a session terminal. Opts: `:cmd` + `:args` (the harness command; default the login shell),
  `:cols`/`:rows` (default 80x24), `:notify` (a pid pinged on screen changes), `:name`.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "The screen as a grid of `{grapheme, fg, bg, flags}` cells."
  def cells(term), do: GenServer.call(term, :cells)

  @doc "Encode a key event and write it to the PTY — a native keystroke."
  def send_key(term, %Ghostty.KeyEvent{} = event), do: GenServer.call(term, {:key, event})

  @doc "Resize the emulator AND the PTY (SIGWINCH to the child)."
  def resize(term, cols, rows), do: GenServer.call(term, {:resize, cols, rows})

  @impl true
  def init(opts) do
    cols = opts[:cols] || @default_cols
    rows = opts[:rows] || @default_rows
    cmd = opts[:cmd] || System.get_env("SHELL") || "/bin/bash"
    args = opts[:args] || []

    {:ok, term} = Terminal.start_link(cols: cols, rows: rows)
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

  def handle_info({:exit, status}, state) do
    notify(state, {:exited, status})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:cells, _from, state), do: {:reply, Terminal.cells(state.term), state}

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
