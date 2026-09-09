defmodule Mix.Tasks.Menard.Mcp do
  @shortdoc "Serve Menard over stdio as an MCP server (for Claude Code / a bare pi)"
  @moduledoc """
  `mix menard.mcp` — the standalone door: the same verbs as `mix menard.*`, over stdio, every
  path scoped to `MENARD_ROOT` (else the caller's directory). Register once:

      claude mcp add menard -- mise run menard -- mcp
  """
  use Mix.Task

  @impl true
  def run(_argv) do
    Mix.Task.run("app.start", ["--no-compile"])
    {:ok, _} = Supervisor.start_child(Menard.Supervisor, {Menard.MCP, transport: :stdio})
    Process.sleep(:infinity)
  end
end
