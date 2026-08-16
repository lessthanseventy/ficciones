defmodule Funes.Arbiter do
  @moduledoc """
  The terminal arbiter — a **capability, not a product** (§8, aleph §6). Waking an
  external agent session means poking its pane so a turn happens; how that poke is
  delivered (Herdr `agent prompt`, tmux `send-keys`, …) is a local backend the
  design never names. Elixir decides *who* to wake; the arbiter *actuates*.

  The backend is chosen by config — `config :funes, :arbiter, SomeModule` — and
  defaults to `Funes.Arbiter.Inert`, which does nothing but log. A real Herdr/tmux
  backend is wired on the machine that has those panes; funes' own tests use a
  capturing backend. Nothing here shells out.
  """
  @callback wake(pane_ref :: String.t(), prompt :: String.t()) :: :ok | {:error, term()}

  @doc """
  Spawn a FRESH pane for a thread whose identity block is `exports` (the `export FUNES_*`
  from `Funes.MCP.Spawn`) — the other actuation the arbiter owns (aleph §2d, the cold-thread
  strand §4c.3). `{:ok, pane_ref}` with the new pane the backend assigned, or `{:error, term}`
  (an inert backend cannot spawn — `{:error, :inert}`). Both aleph's `s` verb and the
  switchboard's autonomous wake call THIS, so the "how to open a pane" seam has one home.
  """
  @callback spawn(exports :: String.t()) :: {:ok, pane_ref :: String.t()} | {:error, term()}

  @doc "The configured backend (defaults to the inert one)."
  def impl, do: Application.get_env(:funes, :arbiter, Funes.Arbiter.Inert)

  @doc "Wake the pane behind an opaque pane_ref, via the configured backend."
  def wake(pane_ref, prompt), do: impl().wake(pane_ref, prompt)

  @doc "Spawn a fresh pane for a thread's `exports` block, via the configured backend."
  def spawn(exports), do: impl().spawn(exports)
end

defmodule Funes.Arbiter.Inert do
  @moduledoc """
  The default arbiter: it pokes nothing and says so. A machine with no terminal
  capability wired still runs the whole design — the wake is a no-op that logs,
  never a crash (§8, degrade honestly).
  """
  @behaviour Funes.Arbiter

  require Logger

  @impl true
  def wake(pane_ref, _prompt) do
    Logger.debug("arbiter(inert): would wake pane #{inspect(pane_ref)}")
    :ok
  end

  @impl true
  def spawn(_exports) do
    Logger.debug("arbiter(inert): would spawn a pane")
    {:error, :inert}
  end
end

defmodule Funes.Arbiter.Tmux do
  @moduledoc """
  The real terminal backend (tlön component 2): a poke is `tmux send-keys` into the
  pane behind an opaque `pane_ref` (a global `%N` id the harness registered). Wired by
  `config :funes, :arbiter, Funes.Arbiter.Tmux` on a machine that has panes; funes stays
  bounded — it shells a `tmux` binary (machine capability), it does NOT import aleph's
  own `Aleph.Tmux` (funes must never reach up into a sibling module).

  **Poking an agent is not typing into a production console (§8).** Causing a turn is
  the entire point, so the poke SENDS Enter deliberately — and it SANITIZES rather than
  failing closed: a message body with embedded newlines is collapsed to one clean line
  (`sanitize/1`) before `send-keys -l`, so a stray newline can't submit mid-text. §8's
  fail-closed rule governs a production write, a different actuation this is not.

  `wake/2` is the effect; `sanitize/1` and `argv/2` are pure and tested. A missing tmux
  or a dead pane is surfaced as `{:error, _}` (the switchboard logs it) — never a crash.
  """
  @behaviour Funes.Arbiter

  @impl true
  def wake(pane_ref, prompt), do: pane_ref |> argv(prompt) |> run_all()

  @impl true
  def spawn(exports) do
    session = Application.get_env(:funes, :spawn_session, "tlon")
    launcher = Application.get_env(:funes, :spawn_launcher, "mise exec -- pi")
    cwd = Application.get_env(:funes, :spawn_cwd) || File.cwd!()
    # A DEDICATED detached session holds every harness as a window: `new-session` conjures it
    # (aleph runs in ghostty via termbox, NOT inside tmux, so bare `new-window` has no server or
    # target session to attach to — the silent-fail bug), `new-window` adds to it once it exists.
    # aleph renders these panes in its Sessions space via capture-pane; nobody attaches to tmux.
    verb = if has_session?(session), do: :window, else: :session
    exports |> spawn_argv(verb, session, launcher, cwd) |> run_capture()
  end

  @doc """
  The tmux invocation a spawn is: a pane in the dedicated detached session `session`, opened in
  `cwd` (a LOGIN shell, so the nix profile is on PATH) that sources the funes env block then
  `exec`s `launcher` — so the window IS the harness session. `:session` creates the detached
  session (first harness = window 1); `:window` adds to it. `-c cwd` lets `mise` find
  `mise.toml`; `-P -F` prints the new pane id back. §8 keeps the concrete launcher in config.
  """
  def spawn_argv(verb, exports, session, launcher, cwd) do
    tail = ["-c", cwd, "-P", "-F", "#\{pane_id}", "bash", "-lc", exports <> "\nexec " <> launcher]

    case verb do
      :session -> ["new-session", "-d", "-s", session | tail]
      :window -> ["new-window", "-t", session | tail]
    end
  end

  defp has_session?(session) do
    match?({_, 0}, System.cmd("tmux", ["has-session", "-t", session], stderr_to_stdout: true))
  rescue
    ErlangError -> false
  end

  @doc """
  Collapse a prompt to one clean line: control bytes (newlines, tabs, NUL) become
  spaces, whitespace runs collapse, ends trimmed — so the nudge is one line and a
  newline in the body never acts as Enter.
  """
  def sanitize(prompt) do
    prompt
    |> String.replace(~r/[[:cntrl:]]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  The two tmux invocations a poke is: send the SANITIZED text literally (`-l`), then
  `Enter` as a separate keystroke — so submit is a deliberate act, not a byte in the text.
  """
  def argv(pane_ref, prompt) do
    text = sanitize(prompt)

    [
      ["send-keys", "-t", pane_ref, "-l", text],
      ["send-keys", "-t", pane_ref, "Enter"]
    ]
  end

  # Run each invocation in order, stopping at the first failure. tmux missing (System.cmd
  # raises) or a non-zero exit is surfaced, never swallowed — a lost nudge must be visible.
  defp run_all([]), do: :ok

  defp run_all([args | rest]) do
    case run(args) do
      :ok -> run_all(rest)
      error -> error
    end
  end

  defp run(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, code} -> {:error, {:tmux_exit, code, String.trim(out)}}
    end
  rescue
    ErlangError -> {:error, :tmux_missing}
  end

  # Like run/1 but returns the captured stdout on success — the new pane id from `-P -F`.
  defp run_capture(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, {:tmux_exit, code, String.trim(out)}}
    end
  rescue
    ErlangError -> {:error, :tmux_missing}
  end
end

defmodule Funes.Arbiter.Test do
  @moduledoc """
  A capturing arbiter for tests: it sends `{:woke, pane_ref, prompt}` to the
  pid in `config :funes, :test_pid`, so a test can assert exactly which panes the
  switchboard decided to wake — without a real terminal.
  """
  @behaviour Funes.Arbiter

  @impl true
  def wake(pane_ref, prompt) do
    if pid = Application.get_env(:funes, :test_pid), do: send(pid, {:woke, pane_ref, prompt})
    :ok
  end

  @impl true
  def spawn(exports) do
    if pid = Application.get_env(:funes, :test_pid), do: send(pid, {:spawned, exports})
    {:ok, "%test-pane"}
  end
end
