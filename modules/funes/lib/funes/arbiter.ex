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
  @callback wake(workspace_ref :: String.t(), prompt :: String.t()) :: :ok | {:error, term()}

  @doc "The configured backend (defaults to the inert one)."
  def impl, do: Application.get_env(:funes, :arbiter, Funes.Arbiter.Inert)

  @doc "Wake the pane behind an opaque workspace_ref, via the configured backend."
  def wake(workspace_ref, prompt), do: impl().wake(workspace_ref, prompt)
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
  def wake(workspace_ref, _prompt) do
    Logger.debug("arbiter(inert): would wake pane #{inspect(workspace_ref)}")
    :ok
  end
end

defmodule Funes.Arbiter.Test do
  @moduledoc """
  A capturing arbiter for tests: it sends `{:woke, workspace_ref, prompt}` to the
  pid in `config :funes, :test_pid`, so a test can assert exactly which panes the
  switchboard decided to wake — without a real terminal.
  """
  @behaviour Funes.Arbiter

  @impl true
  def wake(workspace_ref, prompt) do
    if pid = Application.get_env(:funes, :test_pid), do: send(pid, {:woke, workspace_ref, prompt})
    :ok
  end
end
