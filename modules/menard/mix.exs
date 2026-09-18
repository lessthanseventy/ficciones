defmodule Menard.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lessthanseventy/menard"

  # AST-aware edits and introspection on Sourceror, a project of its own so `mix menard.*` runs
  # even while the app being edited does not compile.
  # `precommit` ends in `test`, so it must run in :test — mix infers that for tasks it knows, not
  # for an alias.
  def cli, do: [preferred_envs: [precommit: :test]]

  def project do
    [
      app: :menard,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      description:
        "AST-aware editing for Elixir: every verb parses the file, changes the tree and parse-checks what it writes.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      deps: [
        {:sourceror, "~> 1.12"},
        # the stdio MCP door (`mix menard.mcp`): the same functions for any harness that speaks MCP
        {:anubis_mcp, "~> 2.0"},
        {:ex_doc, "~> 0.34", only: :dev, runtime: false}
      ],
      # `menard run check` runs `mix precommit` like it does for every other project; without this
      # alias the one tool in the repo could not gate itself.
      aliases: [precommit: ["format --check-formatted", "compile --warnings-as-errors", "test"]]
    ]
  end

  # The package is the LIBRARY and its mix tasks. `bin/menard` and the plugin manifest stay out of
  # it: they run from THIS project, with its own deps fetched, which a package unpacked into
  # someone else's `deps/` does not have. The tool installs from git, the library from hex.
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"}
    ]
  end

  defp docs do
    [main: "readme", source_ref: "v#{@version}", extras: ["README.md", "AGENTS.md", "CHANGELOG.md"]]
  end

  def application, do: [extra_applications: [:logger], mod: {Menard.Application, []}]
end
