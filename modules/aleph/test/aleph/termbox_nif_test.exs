defmodule Aleph.TermboxNifTest do
  use ExUnit.Case, async: true

  # raxol_terminal 2.6.1's Makefile copies the built termbox2 NIF into the build-output
  # priv only inside its link recipe, which `make` skips whenever the .so already exists
  # (e.g. a persisted deps/ artifact surviving an `_build` wipe). The NIF loader reads
  # `:code.priv_dir(:raxol_terminal)`, so a missing copy there is a runtime `:nif_not_loaded`
  # — the crash that killed the first `mise run aleph:run`. aleph's compile step
  # (`ensure_termbox_nif/1` in mix.exs) guarantees the copy; this pins that invariant.
  test "termbox2 NIF .so is present at the loader's priv path" do
    so = Path.join(to_string(:code.priv_dir(:raxol_terminal)), "termbox2_nif.so")

    assert File.exists?(so),
           "termbox2_nif.so missing at #{so} — aleph's compile step must copy it there " <>
             "(see ensure_termbox_nif/1 in mix.exs). Without it tb_init/0 raises :nif_not_loaded."
  end

  # raxol_terminal 2.6.1's termbox2 refreshes its cached terminal size ONLY inside the poll path
  # (tb_poll_event → update_term_size + resize_cellbufs), and aleph never polls — Raxol's Driver
  # owns input — so tb_width()/tb_height() would stay frozen at tb_init size and the layout clips
  # to the old width (void on the right after a widen). aleph's compile step patches in a public
  # `tb_resize/0` (C in termbox_impl.c + stub in termbox2_nif.ex; see ensure_termbox_nif/1 and
  # ensure_termbox_resize_stub/1 in mix.exs), which the cockpit calls each tick. This pins that the
  # patch landed and the NIF module exports it. Not invoked here: tb_resize/0 queries the real tty
  # via update_term_size, which is only safe after tb_init (a real terminal) — not in a test.
  test "termbox2 NIF exports the aleph tb_resize/0 size-refresh patch" do
    # function_exported?/3 sees only LOADED modules; force the load first (safe — loading the NIF
    # lib registers functions but does not call tb_init, so no tty interaction).
    {:module, _} = Code.ensure_loaded(:termbox2_nif)

    assert function_exported?(:termbox2_nif, :tb_resize, 0),
           ":termbox2_nif.tb_resize/0 missing — the compile-time NIF patch didn't apply " <>
             "(see ensure_termbox_nif/1 + ensure_termbox_resize_stub/1 in mix.exs). Without it " <>
             "the cockpit layout stays frozen at tb_init size after a window resize."
  end
end
