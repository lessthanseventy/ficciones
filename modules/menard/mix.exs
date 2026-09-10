defmodule Menard.MixProject do
  use Mix.Project

  # The Elixir repo tools (docs/plans/2026-09-08-elixir-repo-tools-design.md): AST-aware edits
  # and introspection on Sourceror, as a project of their own so `mix menard.*` runs even while the
  # app being edited does not compile. The server depends on it for the coworkers' MCP verbs.
  # `precommit` ends in `test`, so it must run in :test — mix infers that for tasks it knows, not
  # for an alias.
  def cli, do: [preferred_envs: [precommit: :test]]

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
      ],
      # `menard run check --in modules/menard` runs `mix precommit` like it does for every other
      # project; without this alias the one tool in the repo could not gate itself.
      aliases: [precommit: ["format --check-formatted", "compile --warnings-as-errors", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {Menard.Application, []}]
end
