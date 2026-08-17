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

  describe "bracketed paste markers (the raxol paste dep-patch)" do
    # aleph enables \e[?2004h on the host tty, so ghostty wraps a paste in \e[200~…\e[201~. The
    # self-healed InputParser surfaces the markers as paste-start/paste-end events and the content
    # between them as ordinary :key events — the cockpit's paste buffer collects those and forwards
    # the whole block. If this decode regresses (a raxol bump shipping an unpatched parser), a paste
    # decodes as individual keystrokes again and every newline submits.
    test "a bracketed paste decodes to paste-start, content keys, paste-end" do
      events = InputParser.parse("\e[200~hello\nworld\e[201~")

      assert [
               %{type: :paste, data: %{phase: :start}},
               h,
               _e,
               _l1,
               _l2,
               _o,
               enter,
               w,
               _o2,
               _r,
               _l3,
               _d,
               %{type: :paste, data: %{phase: :end}}
             ] = events

      assert h.data.key == :char and h.data.char == "h"
      assert enter.data.key == :enter
      assert w.data.char == "w"
    end

    test "an empty paste is just start then end, no content keys" do
      assert [%{type: :paste, data: %{phase: :start}}, %{type: :paste, data: %{phase: :end}}] =
               InputParser.parse("\e[200~\e[201~")
    end

    test "a paste with a tab keeps the tab as a :key tab (the buffer turns it back into \\t)" do
      events = InputParser.parse("\e[200~a\tb\e[201~")
      assert [%{type: :paste, data: %{phase: :start}}, a, tab, b, %{type: :paste, data: %{phase: :end}}] = events
      assert a.data.char == "a"
      assert tab.data.key == :tab
      assert b.data.char == "b"
    end
  end
end
