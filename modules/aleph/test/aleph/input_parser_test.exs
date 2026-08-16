defmodule Aleph.InputParserTest do
  @moduledoc """
  A contract test for the raxol input parser's Kitty CSI-u decode — the path that makes
  shift+enter reach aleph with its shift bit. The driver enables Kitty disambiguate mode
  (\\e[>1u) on the host tty, so a host like ghostty sends \\e[13;2u for shift+enter; this
  asserts the parser turns that into `%{key: :enter, shift: true}`. Aleph's tmux-style
  input model forwards that to the embedded terminal, which (with its own Kitty protocol
  armed) encodes a real shifted enter. If this decode regresses, shift+enter silently
  becomes a no-op again.
  """
  use ExUnit.Case, async: true

  alias Raxol.Terminal.ANSI.InputParser

  test "shift+enter decodes from Kitty CSI-u (\\e[13;2u) to enter with shift" do
    [event] = InputParser.parse("\e[13;2u")
    assert event.type == :key
    assert event.data.key == :enter
    assert event.data.shift == true
  end

  test "ctrl+enter decodes from \\e[13;5u to enter with ctrl" do
    [event] = InputParser.parse("\e[13;5u")
    assert event.data.key == :enter
    assert event.data.ctrl == true
  end

  test "shift+ctrl+enter decodes from \\e[13;6u to enter with shift+ctrl" do
    [event] = InputParser.parse("\e[13;6u")
    assert event.data.key == :enter
    assert event.data.shift == true
    assert event.data.ctrl == true
  end

  test "an unmodified CSI-u enter (\\e[13u) decodes to plain enter, no mods" do
    [event] = InputParser.parse("\e[13u")
    assert event.data.key == :enter
    refute event.data[:shift]
    refute event.data[:ctrl]
  end

  test "shift+tab decodes from \\e[9;2u to tab with shift (parity with the legacy \\e[Z path)" do
    [event] = InputParser.parse("\e[9;2u")
    assert event.data.key == :tab
    assert event.data.shift == true
  end

  test "a CSI-u sequence carrying an event-type field (3rd param) still decodes" do
    # Kitty sends press=1/repeat=2/release=3 as a third param; release for shift+enter.
    [event] = InputParser.parse("\e[13;2;3u")
    assert event.data.key == :enter
    assert event.data.shift == true
  end

  test "plain \\r still decodes to enter (the legacy path is unchanged by disambiguate)" do
    [event] = InputParser.parse("\r")
    assert event.data.key == :enter
    refute event.data[:shift]
  end
end
