defmodule Menard.MixProject do
  use Mix.Project

  # The Elixir repo tools (docs/plans/2026-09-08-elixir-repo-tools-design.md): AST-aware edits
  # and introspection on Sourceror, as a project of their own so `mix menard.*` runs even while the
  # app being edited does not compile. The server depends on it for the coworkers' MCP verbs.
  def project do
    [
      app: :menard,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: [
        {:sourceror, "~> 1.12"},
        # the stdio MCP door (`mix menard.mcp`): the same functions for a harness outside tlon
        {:anubis_mcp, "~> 2.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {Menard.Application, []}]
end
