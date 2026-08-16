defmodule Aleph.CockpitTest do
  @moduledoc """
  The cockpit is a TTY-grabbing GenServer, so only its PURE seams are unit-tested. `tmux_keys/1`
  is the translation a forwarded key crosses to reach the focused pane — the exact seam where a
  missing clause silently drops a key (a forwarded Esc that vanished trapped the operator in pi's
  fullscreen menu). Every key the keymap can forward must translate to something.
  """
  use ExUnit.Case, async: true

  alias Aleph.Cockpit

  test "Esc translates to the tmux Escape key — the fix for being trapped in a focused menu" do
    assert Cockpit.tmux_keys(%{key: :escape}) == [{:key, "Escape"}]
  end

  test "Ctrl+C forwards as C-c to the pane (cancel the app), not an aleph quit" do
    assert Cockpit.tmux_keys(%{key: :char, char: "c", ctrl: true}) == [{:key, "C-c"}]
  end

  test "a printable char is sent literally; Enter/Backspace/Tab/arrows are named keys" do
    assert Cockpit.tmux_keys(%{key: :char, char: "x"}) == [{:text, "x"}]
    assert Cockpit.tmux_keys(%{key: :enter}) == [{:key, "Enter"}]
    assert Cockpit.tmux_keys(%{key: :backspace}) == [{:key, "BSpace"}]
    assert Cockpit.tmux_keys(%{key: :tab}) == [{:key, "Tab"}]
    assert Cockpit.tmux_keys(%{key: :up}) == [{:key, "Up"}]
  end

  test "every key the keymap forwards to a focused pane has a translation (none silently dropped)" do
    # These are the events Aleph.Keymap's center-focused catch-all forwards. If the keymap grows a
    # forwarded key, add it here AND to tmux_keys — a `[]` here is a key that vanishes.
    forwardable = [
      %{key: :escape},
      %{key: :enter},
      %{key: :backspace},
      %{key: :delete},
      %{key: :tab},
      %{key: :up},
      %{key: :down},
      %{key: :left},
      %{key: :right},
      %{key: :home},
      %{key: :end},
      %{key: :page_up},
      %{key: :page_down},
      %{key: :char, char: "a"},
      %{key: :char, char: "c", ctrl: true}
    ]

    for event <- forwardable do
      assert Cockpit.tmux_keys(event) != [], "no translation for #{inspect(event)} — it would vanish"
    end
  end
end
