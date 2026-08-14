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
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Funes.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, ">= 0.17.0"}
    ]
  end
end
