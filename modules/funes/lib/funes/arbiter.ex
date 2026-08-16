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

  @doc "The configured backend (defaults to the inert one)."
  def impl, do: Application.get_env(:funes, :arbiter, Funes.Arbiter.Inert)

  @doc "Wake the pane behind an opaque pane_ref, via the configured backend."
  def wake(pane_ref, prompt), do: impl().wake(pane_ref, prompt)
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
end
