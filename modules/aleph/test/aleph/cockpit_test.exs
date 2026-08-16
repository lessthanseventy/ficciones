defmodule Aleph.CockpitTest do
  @moduledoc """
  The cockpit is a TTY-grabbing GenServer, so only its PURE seams are unit-tested. `ghostty_key/1`
  is the translation a forwarded key crosses to reach the focused session's embedded terminal —
  aleph key event → `Ghostty.KeyEvent`, which the emulator encodes to PTY bytes. A wrong or missing
  mapping is a key that misfires or vanishes, so it earns its own test.
  """
  use ExUnit.Case, async: true

  alias Aleph.Cockpit
  alias Ghostty.KeyEvent

  test "a printable char carries its utf8 and its key atom" do
    ev = Cockpit.ghostty_key(%{key: :char, char: "x"})
    assert %KeyEvent{key: :x, utf8: "x"} = ev
  end

  test "Ctrl+C maps to key :c with a ctrl mod — the emulator encodes it to ^C" do
    ev = Cockpit.ghostty_key(%{key: :char, char: "c", ctrl: true})
    assert ev.key == :c
    assert :ctrl in ev.mods
  end

  test "Esc, Enter, Tab, Backspace map straight through" do
    assert %KeyEvent{key: :escape} = Cockpit.ghostty_key(%{key: :escape})
    assert %KeyEvent{key: :enter} = Cockpit.ghostty_key(%{key: :enter})
    assert %KeyEvent{key: :tab} = Cockpit.ghostty_key(%{key: :tab})
    assert %KeyEvent{key: :backspace} = Cockpit.ghostty_key(%{key: :backspace})
  end

  test "arrows map to the ghostty arrow_* keys" do
    assert %KeyEvent{key: :arrow_up} = Cockpit.ghostty_key(%{key: :up})
    assert %KeyEvent{key: :arrow_down} = Cockpit.ghostty_key(%{key: :down})
    assert %KeyEvent{key: :arrow_left} = Cockpit.ghostty_key(%{key: :left})
    assert %KeyEvent{key: :arrow_right} = Cockpit.ghostty_key(%{key: :right})
  end

  test "a digit maps to its :digit_N key" do
    assert %KeyEvent{key: :digit_7, utf8: "7"} = Cockpit.ghostty_key(%{key: :char, char: "7"})
  end

  test "an unmappable key is nil — dropped, never misdelivered" do
    assert Cockpit.ghostty_key(%{key: :f5}) == nil
  end

  describe "ghostty_key: Kitty keyboard encoding contract" do
    # pi's TUI decodes Kitty sequences (\e[13;2u for shift+enter, \e[118;5u for ctrl+v). The Kitty
    # encoder needs the key's UNSHIFTED codepoint to build \e[<cp>;<mods>u for a modified printable;
    # without it the modifier is dropped (ctrl+v → "v") and pi's binding misfires.
    test "a char key carries its unshifted codepoint so modifiers survive Kitty encoding" do
      ev = Cockpit.ghostty_key(%{key: :char, char: "v", ctrl: true})
      assert %KeyEvent{key: :v, utf8: "v", mods: [:ctrl], unshifted_codepoint: ?v} = ev
    end

    test "an uppercase letter's unshifted codepoint is the lowercase codepoint (shift+v → ?v)" do
      ev = Cockpit.ghostty_key(%{key: :char, char: "V", shift: true})
      assert %KeyEvent{key: :v, utf8: "V", mods: [:shift], unshifted_codepoint: ?v} = ev
    end

    test "a digit carries its own codepoint" do
      ev = Cockpit.ghostty_key(%{key: :char, char: "5"})
      assert ev.unshifted_codepoint == ?5
    end
  end
end
