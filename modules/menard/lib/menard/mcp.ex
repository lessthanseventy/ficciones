defmodule Menard.MCP do
  @moduledoc """
  The standalone door (design step 5): a stdio MCP server exposing the SAME `Menard.*` functions
  for a harness outside tlon — Claude Code, a bare pi. No identity: every path is scoped to the
  ROOT the server was launched for (`MENARD_ROOT`, else the cwd); a path outside it is refused.
  tlon's MCP stays the coworkers' door, scoped to a thread's worktree there.

      claude mcp add menard -- mise run menard -- mcp        # from the repo root
  """
  use Anubis.Server, name: "menard", version: "0.1.0", capabilities: [:tools]

  component(Menard.MCP.Rename, name: "rename")
  component(Menard.MCP.Clause, name: "clause")
  component(Menard.MCP.Outline, name: "outline")
  component(Menard.MCP.Find, name: "find")
  component(Menard.MCP.Run, name: "run")

  @doc "The directory every path resolves under."
  def root, do: System.get_env("MENARD_ROOT") || Menard.caller_dir()

  @doc "A path under the root, or a refusal — no edit escapes the launch directory."
  def resolve(path) do
    root = root()
    abs = Path.expand(path, root)

    if String.starts_with?(abs, root <> "/") or abs == root,
      do: {:ok, abs},
      else: {:error, "refused: #{path} is outside #{root}"}
  end

  @doc "Every path resolved, or the first refusal — no partial edits."
  def resolve_all(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn p, {:ok, acc} ->
      case resolve(p) do
        {:ok, abs} -> {:cont, {:ok, acc ++ [abs]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end
end
