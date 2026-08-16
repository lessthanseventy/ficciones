defmodule Aleph.Arbiter do
  @moduledoc """
  The arbiter backend for the aleph hub — how funes' switchboard actuates a wake now that sessions
  are embedded ghostty terminals aleph owns, not tmux panes. Configured as `config :funes, :arbiter,
  Aleph.Arbiter`: funes calls it through the behaviour seam (§8), never importing aleph — the
  dependency stays one-directional, funes → nothing.

  - `wake(session, prompt)` — write the prompt into the session's terminal (keyed by its thread) so
    the harness takes a turn. Poking an agent is not a production write (§8): it SANITIZES the
    prompt to one clean line and appends Enter, rather than failing closed.
  - `spawn(exports)` — open a fresh terminal for the thread named in the env block (the cold-thread
    strand), the same `Aleph.Sessions.spawn_harness` the `s` verb uses.
  """
  @behaviour Funes.Arbiter

  alias Aleph.Sessions
  alias Aleph.Terminal

  @impl Funes.Arbiter
  def wake(%{thread_id: thread_id}, prompt) do
    case Sessions.terminal(thread_id) do
      nil -> {:error, :no_terminal}
      term -> Terminal.feed(term, sanitize(prompt) <> "\r")
    end
  end

  @impl Funes.Arbiter
  def spawn(exports) do
    case thread_id(exports) do
      nil -> {:error, :no_thread_in_exports}
      thread_id -> Sessions.spawn_harness(thread_id, exports)
    end
  end

  @doc "Collapse a prompt to one clean line — control bytes → spaces, runs collapsed, trimmed."
  def sanitize(prompt) do
    prompt
    |> String.replace(~r/[[:cntrl:]]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc "The thread id in an `export FUNES_THREAD=\"N\"` block, or nil."
  def thread_id(exports) do
    case Regex.run(~r/FUNES_THREAD="(\d+)"/, exports) do
      [_whole, id] -> String.to_integer(id)
      _ -> nil
    end
  end
end
