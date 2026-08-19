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

  test "EVERY letter and digit maps without crashing (atom-intern safety)" do
    # Iterate by codepoint so no literal key atom (`:o`, `:p`, …) is interned by this test — the trap
    # that let `to_existing_atom` crash the cockpit on a keypress whose atom existed nowhere. With
    # `to_atom` every printable maps; with `to_existing_atom` the first un-interned letter raises.
    for c <- Enum.map(?a..?z, &<<&1>>) ++ Enum.map(?A..?Z, &<<&1>>) ++ Enum.map(?0..?9, &<<&1>>) do
      assert %KeyEvent{utf8: ^c} = Cockpit.ghostty_key(%{key: :char, char: c})
    end
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

    test "crash_issue_open? reads the capped %{shown, more} shape open_issues_for_thread returns" do
      issues = %{shown: [%{summary: "aleph crashed: boom"}], more: 3}
      assert Cockpit.crash_issue_open?(issues, "aleph crashed: boom")
      refute Cockpit.crash_issue_open?(issues, "aleph crashed: other")
      refute Cockpit.crash_issue_open?(%{shown: [], more: 0}, "aleph crashed: boom")
    end
  end

  describe "profile_launcher/1: the Tlön window-0 command runs pi from its profile's config dir" do
    @profile %Aleph.Profile{name: "tlon"}

    test "attaches-or-creates the standing tlon session" do
      assert Cockpit.profile_launcher(@profile) =~ "new-session -A -s tlon"
    end

    test "runs on the coworker's PRIVATE tmux server with the profile's persistence-free config" do
      cmd = Cockpit.profile_launcher(@profile)
      assert cmd =~ "tmux -L #{Aleph.Profiles.socket("tlon")} "
      assert cmd =~ "-f #{Aleph.Profiles.config_dir("tlon")}/tmux.conf"
    end

    test "points pi at the profile's config dir and carries the funes identity into the session env" do
      cmd = Cockpit.profile_launcher(@profile)
      assert cmd =~ "PI_CODING_AGENT_DIR=#{Aleph.Profiles.config_dir("tlon")}"
      # The tlon coworker is a funes citizen (machine scope, @tlon_funes_mcp reads ${FUNES_MCP_URL}),
      # so the identity is `-e`'d into the tmux SESSION env — durable across a pi respawn, not just
      # pi's one-shot process env. (Supersedes the old "self-contained, no funes env" design.)
      assert cmd =~ ~s(-e FUNES_MCP_URL="$FUNES_MCP_URL")
      assert cmd =~ ~s(-e FUNES_AUTHOR="$FUNES_AUTHOR")
      assert cmd =~ "MANOS_RELOAD_CMD="
    end

    test "MANOS_RELOAD_CMD carries the config dir so a manos/reload respawn stays on-profile" do
      cmd = Cockpit.profile_launcher(@profile)

      assert cmd =~
               "MANOS_RELOAD_CMD=env PI_CODING_AGENT_DIR=#{Aleph.Profiles.config_dir("tlon")} mise exec -- pi --continue"
    end

    test "a profile with a persona adds --append-system-prompt; without one, none" do
      refute Cockpit.profile_launcher(@profile) =~ "--append-system-prompt"
      withp = Cockpit.profile_launcher(%Aleph.Profile{name: "tlon", system_prompt: "be terse"})
      assert withp =~ "--append-system-prompt #{Aleph.Profiles.config_dir("tlon")}/system_prompt.md"
    end

    test "still launches pi as window 0's command" do
      assert Cockpit.profile_launcher(@profile) =~ "mise exec -- pi"
    end

    test "chrome-off + copy-mode style live in the profile tmux.conf now, not chained set-options" do
      cmd = Cockpit.profile_launcher(@profile)
      assert cmd =~ "new-session -A -s tlon -n tertius"
      refute cmd =~ "set-option"

      conf = Aleph.Profiles.tmux_conf()
      assert conf =~ "set -g status off"
      assert conf =~ "set -g 'status-format[0]' ''"
      assert conf =~ "set -g pane-border-status off"
      assert conf =~ "set -g mode-style 'bg=#3b4261,fg=#c0caf5'"
    end
  end

  describe "machine_spawn_due?/2: the Tlön coworker backoff gate" do
    test "a fresh cockpit (no prior failure) is due — even though BEAM monotonic time is NEGATIVE" do
      # The bug: machine_retry_at started at 0 and the guard was `now < retry_at`. BEAM monotonic
      # time starts as a large NEGATIVE number, so `now < 0` was ALWAYS true and the spawn line was
      # never reached — Tlön could never start its coworker. The "no backoff pending" sentinel must
      # be honoured regardless of the sign of `now`.
      now = System.monotonic_time(:millisecond)
      assert now < 0, "precondition: this box's monotonic clock is negative (#{now})"
      assert Cockpit.machine_spawn_due?(nil, now)
    end

    test "a pending backoff still in the future is NOT due" do
      now = System.monotonic_time(:millisecond)
      refute Cockpit.machine_spawn_due?(now + 5_000, now)
    end

    test "an elapsed backoff is due again" do
      now = System.monotonic_time(:millisecond)
      assert Cockpit.machine_spawn_due?(now - 1, now)
    end
  end

  describe "parse_tlon_tabs/1: the workspace's windows as tab data" do
    test "each `<active>\\t<index>\\t<name>` line becomes a tab — active flagged, index kept" do
      out = "1\t1\tpi\n0\t2\tclaude\n0\t3\tterm\n"

      assert Cockpit.parse_tlon_tabs(out) == [
               %{name: "pi", active?: true, index: "1"},
               %{name: "claude", active?: false, index: "2"},
               %{name: "term", active?: false, index: "3"}
             ]
    end

    test "empty output (session not up yet) is an empty strip, not a crash" do
      assert Cockpit.parse_tlon_tabs("") == []
    end

    test "a malformed line is dropped, not guessed" do
      assert Cockpit.parse_tlon_tabs("garbage\n1\t1\tpi\n") == [%{name: "pi", active?: true, index: "1"}]
    end
  end

  # The Tlön pi identity must reach the tmux SESSION env, not just pi's one-shot process env, or a
  # continuum/--continue respawn comes up with ${FUNES_MCP_URL} empty and the funes MCP never wires
  # ("Tool not found"). These -e flags put it in the session env, durable across respawns.
  describe "funes_identity_flags/0 — durable FUNES_* wiring for the tlon session" do
    test "emits -e VAR=\"$VAR\" for each funes identity var so bash expands current values" do
      flags = Cockpit.funes_identity_flags()
      assert flags =~ ~s(-e FUNES_MCP_URL="$FUNES_MCP_URL")
      assert flags =~ ~s(-e FUNES_THREAD="$FUNES_THREAD")
      assert flags =~ ~s(-e FUNES_AUTHOR="$FUNES_AUTHOR")
    end
  end

  # run/0's crash-recovery decision: a clean quit ends; a crash relaunches the cockpit in place
  # (funes + the session terminals stay supervised), unless it's crash-looping.
  describe "resurrect_decision/3 — what run/0 does after the cockpit goes DOWN" do
    test "a clean quit (:normal / :shutdown) ends the session, never resurrects" do
      assert Cockpit.resurrect_decision(:normal, 0, 10) == :quit
      assert Cockpit.resurrect_decision(:shutdown, 2, 10) == :quit
    end

    test "a crash relaunches, counting the strike" do
      assert Cockpit.resurrect_decision({:badmatch, nil}, 0, 50) == {:resurrect, 1}
      assert Cockpit.resurrect_decision({:badmatch, nil}, 1, 50) == {:resurrect, 2}
    end

    test "too many rapid crashes in a row stay down instead of spinning the terminal" do
      assert Cockpit.resurrect_decision({:badmatch, nil}, 2, 50) == {:stop, 3}
    end

    test "a cockpit that stayed up a while resets the strike count — an isolated crash still heals" do
      assert Cockpit.resurrect_decision({:badmatch, nil}, 2, 30_000) == {:resurrect, 1}
    end
  end
end
