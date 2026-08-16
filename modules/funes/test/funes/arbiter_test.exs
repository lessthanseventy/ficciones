defmodule Funes.ArbiterTest do
  # The real tmux poke backend (tlön component 2). Waking an agent's pane is NOT
  # typing into a production console (§8): causing a turn is the point, so the poke
  # SENDS Enter deliberately and SANITIZES rather than failing closed — a body with
  # embedded newlines is collapsed to one clean line so a stray newline can't submit
  # mid-text. The live send-keys is the eye-test; the sanitizer and argv are pure.
  use ExUnit.Case, async: true

  alias Funes.Arbiter.Tmux

  describe "sanitize/1 — one clean line, never a mid-text submit" do
    test "collapses embedded newlines to single spaces" do
      assert Tmux.sanitize("first line\nsecond line") == "first line second line"
    end

    test "strips tabs and other control bytes, collapsing whitespace runs" do
      assert Tmux.sanitize("a\tb\r\n\x00c   d") == "a b c d"
    end

    test "trims leading/trailing whitespace left by stripping" do
      assert Tmux.sanitize("\n  hello  \n") == "hello"
    end

    test "leaves an ordinary one-line prompt untouched" do
      assert Tmux.sanitize("New message on thread 7 from Carl: CI is red") ==
               "New message on thread 7 from Carl: CI is red"
    end
  end

  describe "argv/2 — the two tmux invocations a poke is" do
    test "sends the sanitized text literally, THEN Enter as a separate keystroke" do
      assert Tmux.argv("%3", "wake up") == [
               ["send-keys", "-t", "%3", "-l", "wake up"],
               ["send-keys", "-t", "%3", "Enter"]
             ]
    end

    test "the text arg is already sanitized — no raw newline reaches send-keys -l" do
      [[_, _, _, "-l", text], _enter] = Tmux.argv("%3", "line1\nline2")
      refute text =~ "\n"
      assert text == "line1 line2"
    end
  end

  describe "spawn_argv/5 — a pane in the dedicated detached session" do
    test ":session verb creates the detached session (its first harness is window 1)" do
      exports = ~s(export FUNES_TOKEN="abc"\nexport FUNES_THREAD="42")

      ["new-session", "-d", "-s", "tlon", "-c", cwd, "-P", "-F", fmt, "bash", "-lc", script] =
        Tmux.spawn_argv(:session, exports, "tlon", "mise exec -- pi", "/repo")

      # A detached session works whether or not aleph itself runs inside tmux — the bug was that
      # bare `new-window` needs a server + a target session, which a termbox TUI in ghostty lacks.
      assert cwd == "/repo"
      assert fmt == "#\{pane_id}"
      assert script =~ ~s(export FUNES_TOKEN="abc")
      assert script =~ "exec mise exec -- pi"
    end

    test ":window verb adds a harness to the existing session" do
      ["new-window", "-t", "tlon", "-c", "/repo", "-P", "-F", "#\{pane_id}", "bash", "-lc", script] =
        Tmux.spawn_argv(:window, ~s(export FUNES_THREAD="7"), "tlon", "pi", "/repo")

      assert script =~ "exec pi"
    end
  end
end
