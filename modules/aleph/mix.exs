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
      # Self-heal the termbox2 NIF after every compile (see ensure_termbox_nif/1).
      compile: ["compile", &ensure_termbox_nif/1],
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end

  # raxol_terminal 2.6.1 builds its termbox2 NIF but only copies the .so into the
  # build-output priv INSIDE its Makefile link recipe — which `make` skips whenever the
  # .so already exists (e.g. a deps/ artifact persisting across an `_build` wipe). The
  # loader reads `:code.priv_dir(:raxol_terminal)`, so a missing copy there is a runtime
  # `:nif_not_loaded` crash. We restore it from the deps priv after every compile.
  # Idempotent; a no-op once the copy is in place. Pinned by test/aleph/termbox_nif_test.exs.
  defp ensure_termbox_nif(_args) do
    dest_dir = Path.join([Mix.Project.build_path(), "lib", "raxol_terminal", "priv"])
    dest = Path.join(dest_dir, "termbox2_nif.so")

    unless File.exists?(dest) do
      src =
        [
          ["lib", "termbox2_nif", "priv", "termbox2_nif.so"],
          ["lib", "termbox2_nif", "c_src", "termbox2_nif.so"]
        ]
        |> Enum.map(&Path.join([Mix.Project.deps_path(), "raxol_terminal" | &1]))
        |> Enum.find(&File.exists?/1)

      case src do
        nil ->
          Mix.shell().error(
            "[aleph] termbox2_nif.so not found in deps — run " <>
              "`mise exec -- mix deps.compile raxol_terminal --force`"
          )

        src ->
          File.mkdir_p!(dest_dir)
          File.cp!(src, dest)
          Mix.shell().info("[aleph] restored termbox2_nif.so -> #{Path.relative_to_cwd(dest)}")
      end
    end

    :ok
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
