defmodule Aleph.MixProject do
  use Mix.Project

  # aleph — the cockpit TUI over funes (design: ../../docs/plans/2026-08-15-aleph-tui-design.md).
  # One raxol_core app: sidebars are panels/components over funes' read models; the middle
  # column will later embed a ghostty_ex view of a tmux client. aleph depends on funes and
  # boots its OTP app to subscribe to the Bus; funes never depends on aleph (§8 boundary), and
  # aleph's TUI deps stay quarantined here so funes' dep list stays pristine.
  def project do
    [
      app: :aleph,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Aleph.Application, []}
    ]
  end

  # Run the whole precommit gate (incl. `test`) in the test environment.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Mirror funes' one gate: format, warnings-as-errors, and the suite.
  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end

  defp deps do
    [
      # `runtime: false` for now: aleph uses funes' modules (read models, Bus topics) but
      # does not yet auto-boot funes' OTP app — that waits until the live-Bus wiring step,
      # which needs a test DB for funes' Repo. Flip to a normal dep then.
      {:funes, path: "../funes", runtime: false},
      # The disciplined subset of the Raxol family, NOT the full `raxol` umbrella (which
      # drags in payments/earn/mcp/sensor). `raxol_terminal` = screen buffers + ANSI +
      # input + the termbox2 driver; `raxol_core` = the infra behaviours it sits on (§3).
      {:raxol_terminal, "~> 2.6"},
      {:raxol_core, "~> 2.6"}
    ]
  end
end
