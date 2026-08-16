defmodule Aleph.Spawn do
  @moduledoc """
  The cockpit's `s` verb, actuated (tlön component 3, §2d). aleph IS the serving node — it
  runs the funes MCP server and holds the `Tokens` registry — so it mints identity
  **in-process** (`Funes.MCP.Spawn.join/3`, no rpc into another node) and opens a tmux window
  running the harness with the `export FUNES_*` block sourced. The harness comes up already a
  citizen of the thread: its manos extension reads the env, registers, and briefs.

  aleph may import funes (the dependency direction is aleph → funes; only the reverse is
  banned). The launcher — the actual `pi`/`claude` command — is machine-local config
  (`:aleph, :spawn_launcher`, §8: the harness is not part of the design), and the shell is a
  login shell so mise's PATH is present. `command/2` is pure; the launch is the eye-test.
  """
  alias Funes.MCP.Spawn, as: Funes

  @doc """
  Spawn a harness session onto an EXISTING thread. Joins in-process (mints a token, builds the
  env block), then opens a tmux window running the launcher. Returns `{:ok, pane_id}` (the new
  pane tmux assigned, for the record) or an error from the join or from tmux.
  """
  def session(thread_id, agent_name, opts \\ []) do
    launcher = Keyword.get(opts, :launcher) || Application.get_env(:aleph, :spawn_launcher, "pi")

    with {:ok, %{exports: exports}} <- Funes.join(thread_id, agent_name, opts) do
      exports |> command(launcher) |> run()
    end
  end

  @doc """
  The tmux invocation a spawn is: a new window whose shell sources the funes env block and then
  `exec`s the launcher (so the window IS the session, not a subshell under it). `-P -F` prints
  the new pane's id back, so the caller learns the `pane_ref` tmux assigned.
  """
  def command(exports, launcher) do
    script = exports <> "\nexec " <> launcher
    ["new-window", "-P", "-F", "#\{pane_id}", "bash", "-lc", script]
  end

  defp run(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, {:tmux_exit, code, String.trim(out)}}
    end
  rescue
    ErlangError -> {:error, :tmux_missing}
  end
end
