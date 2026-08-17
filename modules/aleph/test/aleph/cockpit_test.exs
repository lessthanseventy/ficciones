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

  describe "crash_report/1: only a real crash gets logged" do
    test "a clean quit (:normal / :shutdown) produces no report" do
      assert Cockpit.crash_report(:normal) == nil
      assert Cockpit.crash_report(:shutdown) == nil
      assert Cockpit.crash_report({:shutdown, :quit}) == nil
    end

    test "a crash reason is formatted into a report (with the stacktrace, when present)" do
      report = Cockpit.crash_report({%RuntimeError{message: "boom"}, []})
      assert is_binary(report)
      assert report =~ "boom"
    end

    test "crash_summary takes the first non-blank report line (for the filed issue's title)" do
      assert Cockpit.crash_summary("\n** (RuntimeError) boom\n    at foo.ex:1\n") ==
               "** (RuntimeError) boom"
    end
  end

  describe "tlon_launcher/1: the Tlön window-0 command carries the machine identity" do
    # tmux runs window 0's command in the SERVER's environment, not the client's, so FUNES_*
    # exports must ride in via `-e` or pi comes up "not wired".
    @exports """
    export FUNES_MCP_URL="http://127.0.0.1:4041/mcp"
    export FUNES_THREAD="d7f2-abc"
    export FUNES_AUTHOR="pi-machine"\
    """

    test "attaches-or-creates the standing tlon session" do
      assert Cockpit.tlon_launcher(@exports) =~ "new-session -A -s tlon"
    end

    test "forwards every FUNES_* export into the new session's environment" do
      cmd = Cockpit.tlon_launcher(@exports)
      assert cmd =~ "FUNES_MCP_URL=http://127.0.0.1:4041/mcp"
      assert cmd =~ "FUNES_THREAD=d7f2-abc"
      assert cmd =~ "FUNES_AUTHOR=pi-machine"
      assert length(Regex.scan(~r/(^|\s)-e /, cmd)) == 3
    end

    test "still launches pi as window 0's command" do
      assert Cockpit.tlon_launcher(@exports) =~ "mise exec -- pi"
    end

    test "silences tmux's own status bar — aleph draws the Tlön chrome" do
      # Chained onto the one new-session with `\;` (the launcher must stay a single foreground
      # command). Window 0 is named `pi` so the tab strip has a clean label.
      cmd = Cockpit.tlon_launcher(@exports)
      assert cmd =~ "\\; set-option -t tlon status off"
      assert cmd =~ "new-session -A -s tlon -n pi"
    end
  end

  describe "parse_tlon_tabs/1: the workspace's windows as tab data" do
    test "each `<active>\\t<name>` line becomes a tab, active flagged" do
      out = "1\tpi\n0\tclaude\n0\tterm\n"

      assert Cockpit.parse_tlon_tabs(out) == [
               %{name: "pi", active?: true},
               %{name: "claude", active?: false},
               %{name: "term", active?: false}
             ]
    end

    test "empty output (session not up yet) is an empty strip, not a crash" do
      assert Cockpit.parse_tlon_tabs("") == []
    end

    test "a malformed line is dropped, not guessed" do
      assert Cockpit.parse_tlon_tabs("garbage\n1\tpi\n") == [%{name: "pi", active?: true}]
    end
  end
end
