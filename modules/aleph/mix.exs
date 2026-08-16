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
      # Self-heal the termbox2 NIF after every compile (see ensure_termbox_nif/1), and the
      # raxol input-parser Kitty CSI-u patch before it (see ensure_raxol_kitty_parser/1).
      compile: [&ensure_raxol_kitty_parser/1, "compile", &ensure_termbox_nif/1],
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end

  # raxol_terminal 2.6.1 ships a termbox2 NIF with two defects this alias repairs after every
  # compile (both idempotent, pinned by test/aleph/termbox_nif_test.exs). deps/ is gitignored,
  # so the fix can't live in the dep's Makefile — it must re-apply on each build.
  #
  #   1. TRUECOLOR. `termbox_impl.c` defines TB_LIB_OPTS (→ 64-bit `uintattr_t`), but the wrapper
  #      `termbox2_nif.c` does not, so it compiles against the default 16-bit width and truncates
  #      every 24-bit colour handed to `tb_set_cell` — the red byte is dropped, so amber renders
  #      green and pink renders blue. We recompile with `-DTB_OPT_ATTR_W=64` so both translation
  #      units agree on the colour type. Re-runs only when needed (no marker, or the dep rebuilt
  #      the .so newer than our marker).
  #   2. INSTALL. The Makefile copies the .so into build-output priv only inside its link recipe,
  #      which `make` skips when the .so already exists; the loader reads
  #      `:code.priv_dir(:raxol_terminal)`, so a missing copy is a runtime `:nif_not_loaded`.
  @termbox_cflags "-O2 -Wall -Wextra -Wno-unused-parameter -std=c99 -fPIC -Itermbox2 -DTB_OPT_ATTR_W=64"

  defp ensure_termbox_nif(_args) do
    c_src =
      Path.join([Mix.Project.deps_path(), "raxol_terminal", "lib", "termbox2_nif", "c_src"])

    rebuilt? = File.dir?(c_src) and rebuild_termbox_truecolor(c_src)
    install_termbox_nif(rebuilt?)
    :ok
  end

  # raxol_terminal 2.6.1's InputParser has no Kitty keyboard CSI-u decode, so shifted keys
  # (shift+enter) arrive as \e[13;2u and are silently consumed (no event) — the modifier is
  # lost before aleph sees it. deps/ is gitignored, so this self-heals the patch onto the dep
  # source before compile (idempotent — a `defp csi_u_event` marker). When the patch is (re)applied
  # the source mtime advances past the dep's beam, so the `compile` step that follows rebuilds
  # raxol_terminal with the patch. The host-side Kitty disambiguate mode that PRODUCES these
  # sequences is enabled in Aleph.Cockpit itself (no dep patch) — this only teaches the parser
  # to decode them.
  @kitty_parser Path.join([
                  Mix.Project.deps_path(),
                  "raxol_terminal",
                  "lib",
                  "raxol",
                  "terminal",
                  "ansi",
                  "input_parser.ex"
                ])

  # The CSI-u clauses inserted at the head of parse_csi_tilde_one/1's `case`.
  @kitty_csi_u_clauses """
      # Kitty keyboard protocol CSI-u: ESC [ <codepoint> [ ; <mods> [ ; <event> ] ] u.
      # Enabled by Aleph.Cockpit writing \e[>1u (disambiguate) on the host tty. Modified keys
      # with no legacy form — shift+enter (\e[13;2u), ctrl+enter (\e[13;5u), shift+tab
      # (\e[9;2u) — arrive here. Plain keys keep their legacy form (enter stays \r), so this
      # only fires for the modified/disambiguated ones. `mods` is 1 + bitmask (shift=1, alt=2,
      # ctrl=4, meta=8).
      {[cp], ?u, rest} ->
        {csi_u_event(cp, []), rest}

      {[cp, mods], ?u, rest} ->
        {csi_u_event(cp, mods_to_opts(mods)), rest}

      {[cp, mods, _event_type], ?u, rest} ->
        {csi_u_event(cp, mods_to_opts(mods)), rest}

  """

  # The helpers inserted after decode_modifier/1.
  @kitty_csi_u_helpers """
    # Build the opts keyword list for `key_event/2` from a Kitty CSI-u mods field (1 + bitmask).
    # Reuses `decode_modifier/1` (same shift=1/alt=2/ctrl=4 encoding); the meta bit (8) is ignored
    # for now — no binding reads it.
    defp mods_to_opts(mod) when is_integer(mod) do
      {shift, alt, ctrl} = decode_modifier(mod)
      [{:shift, shift}, {:alt, alt}, {:ctrl, ctrl}]
      |> Enum.filter(fn {_, on?} -> on? end)
      |> Enum.map(fn {k, _} -> {k, true} end)
    end

    # A Kitty CSI-u event: map the codepoint to a key atom (special keys) or a :char (printable),
    # then attach the modifier opts. Plain keys with a legacy form (enter=\r, tab=\t, ctrl+v=\x16)
    # never arrive here — only modified or disambiguated ones — so the mapping covers the keys
    # that actually surface as CSI-u under disambiguate mode.
    defp csi_u_event(cp, opts) do
      case kitty_codepoint_to_key(cp) do
        {:key, k} -> key_event(k, opts)
        {:char, c} -> key_event(:char, Keyword.merge(opts, char: c))
      end
    end

    defp kitty_codepoint_to_key(13), do: {:key, :enter}
    defp kitty_codepoint_to_key(9), do: {:key, :tab}
    defp kitty_codepoint_to_key(127), do: {:key, :backspace}
    defp kitty_codepoint_to_key(27), do: {:key, :escape}
    defp kitty_codepoint_to_key(32), do: {:key, :space}
    defp kitty_codepoint_to_key(cp) when cp >= 32 and cp <= 0x10ffff, do: {:char, <<cp::utf8>>}
    defp kitty_codepoint_to_key(_), do: {:key, :unknown}

  """

  defp ensure_raxol_kitty_parser(_args) do
    path = @kitty_parser

    case File.read(path) do
      {:ok, src} ->
        if String.contains?(src, "defp csi_u_event") do
          :ok
        else
          patched =
            src
            |> String.replace(
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n      {[n], ?~, rest} ->",
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n" <>
                @kitty_csi_u_clauses <> "      {[n], ?~, rest} ->"
            )
            |> String.replace(
              "  defp decode_modifier(mod) when is_integer(mod) do\n    bits = mod - 1\n    shift = (bits &&& 1) != 0\n    alt = (bits &&& 2) != 0\n    ctrl = (bits &&& 4) != 0\n    {shift, alt, ctrl}\n  end\n",
              "  defp decode_modifier(mod) when is_integer(mod) do\n    bits = mod - 1\n    shift = (bits &&& 1) != 0\n    alt = (bits &&& 2) != 0\n    ctrl = (bits &&& 4) != 0\n    {shift, alt, ctrl}\n  end\n" <>
                @kitty_csi_u_helpers
            )

          if patched == src do
            Mix.shell().error(
              "[aleph] raxol Kitty CSI-u patch anchor not found in #{path} — " <>
                "did raxol_terminal restructure parse_csi_tilde_one/decode_modifier?"
            )
          else
            File.write!(path, patched)
            Mix.shell().info("[aleph] patched raxol InputParser with Kitty CSI-u decode")
          end
        end

      _ ->
        :ok
    end
  end

  # Recompile the NIF so both translation units carry a 64-bit colour type. `make CFLAGS=...` on
  # the command line overrides the Makefile's `CFLAGS ?=`. Returns true iff a rebuild happened.
  defp rebuild_termbox_truecolor(c_src) do
    marker = Path.join(c_src, ".aleph_truecolor")
    so = Path.join(c_src, "termbox2_nif.so")

    if truecolor_current?(marker, so) do
      false
    else
      Mix.shell().info("[aleph] rebuilding termbox2_nif.so with 24-bit truecolor…")
      System.cmd("make", ["clean"], cd: c_src, stderr_to_stdout: true)

      {out, status} =
        System.cmd("make", ["CFLAGS=#{@termbox_cflags}"], cd: c_src, stderr_to_stdout: true)

      if status == 0 do
        File.write!(marker, "TB_OPT_ATTR_W=64 — full 24-bit colour reaches tb_set_cell\n")
        true
      else
        Mix.shell().error("[aleph] termbox2 truecolor rebuild failed:\n#{out}")
        false
      end
    end
  end

  # Fresh when our marker is at least as new as the built .so; a dep rebuild bumps the .so past it.
  defp truecolor_current?(marker, so) do
    with {:ok, %{mtime: marker_at}} <- File.stat(marker, time: :posix),
         {:ok, %{mtime: so_at}} <- File.stat(so, time: :posix) do
      marker_at >= so_at
    else
      _ -> false
    end
  end

  defp install_termbox_nif(force?) do
    dest_dir = Path.join([Mix.Project.build_path(), "lib", "raxol_terminal", "priv"])
    dest = Path.join(dest_dir, "termbox2_nif.so")

    if force? or not File.exists?(dest) do
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
          Mix.shell().info("[aleph] installed termbox2_nif.so -> #{Path.relative_to_cwd(dest)}")
      end
    end
  end

  defp deps do
    [
      # A live runtime dep: aleph boots funes' OTP app (PubSub + Repo) and subscribes to
      # the Bus (§6). funes never depends on aleph — the boundary is one-directional. Because
      # a dependency's own `config/*.exs` is NOT evaluated when aleph is the root app, aleph
      # supplies funes' Repo config itself (config/config.exs + config/runtime.exs).
      {:funes, path: "../funes"},
      # The disciplined subset of the Raxol family, NOT the full `raxol` umbrella (which
      # drags in payments/earn/mcp/sensor). `raxol_terminal` = screen buffers + ANSI +
      # input + the termbox2 driver; `raxol_core` = the infra behaviours it sits on (§3).
      {:raxol_terminal, "~> 2.6"},
      {:raxol_core, "~> 2.6"},
      # The embedded REAL terminal for the center column (design §4): Ghostty's own VT engine
      # (libghostty-vt) + a PTY, as precompiled NIFs (x86_64/aarch64 Linux, aarch64 macOS — no Zig
      # toolchain). Spawn a session in a PTY, feed its bytes to the emulator, read the cell grid
      # back — a native terminal widget, NOT a captured-and-repainted view (which felt laggy).
      {:ghostty, "~> 0.4"},
      # One styling authority on mix format, same as funes.
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
