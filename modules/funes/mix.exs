defmodule Funes.MixProject do
  use Mix.Project

  # funes — the machine-side memory and coordination layer, as an OTP application.
  # SQLite is the truth (Ecto over ecto_sqlite3); the same single file the spec
  # measured, still sqlite3-inspectable and 2am-repairable.
  def project do
    [
      app: :funes,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # The one internal-CI gate: format, warnings-as-errors, Credo, and the suite.
  # `mix run check` (mise) and any git pre-commit hook run this same alias.
  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --warnings-as-errors"
      ]
    ]
  end

  # Test support (e.g. Funes.TestDB) compiles only under :test.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Funes.Application, []}
    ]
  end

  # Run the whole precommit gate (incl. `test`) in the test environment.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, ">= 0.17.0"},
      # The switchboard's liveness layer (§10): PubSub fans a posted message out to
      # internal consumers. SQLite stays the truth; this only makes it live.
      {:phoenix_pubsub, "~> 2.1"},
      # The sovereign channel (pi doc §2a): funes' MCP server. Anubis owns the
      # protocol lifecycle (JSON-RPC, sessions, auth, version negotiation) so it
      # cannot drift from the MCP spec under our hands; the tools themselves stay
      # thin callers of the contexts — no mirror, one writer.
      {:anubis_mcp, "~> 2.0"},
      # Serves the StreamableHTTP plug, loopback-only. Plumbing, not design — the
      # channel's contract is MCP, whatever serves it.
      {:bandit, "~> 1.0"},
      # Static analysis, part of the precommit gate.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # A mix format plugin: one styling authority so directive order, alias
      # shape and pipe style are never a review comment again.
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
