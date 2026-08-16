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
end
