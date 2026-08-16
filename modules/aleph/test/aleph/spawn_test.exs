defmodule Aleph.SpawnTest do
  # The cockpit's `s` verb actuates a spawn (tlön component 3): join the thread in-process
  # (aleph IS the serving node — no rpc), then open a tmux window running the harness with
  # the funes env sourced, so it comes up a briefed citizen. The tmux `command/2` builder is
  # pure and tested here; the live launch (System.cmd) is the eye-test.
  use ExUnit.Case, async: true

  alias Aleph.Spawn

  describe "command/2 — the tmux new-window invocation" do
    test "sources the funes env, then execs the launcher, capturing the new pane id" do
      exports = ~s(export FUNES_TOKEN="abc"\nexport FUNES_THREAD="42")
      ["new-window", "-P", "-F", fmt, "bash", "-lc", script] = Spawn.command(exports, "pi")

      # -P -F prints the NEW pane's id back, so the caller learns the pane_ref tmux assigned.
      assert fmt == "#\{pane_id}"
      # the whole export block is sourced before the harness starts, so it comes up a citizen
      assert script =~ ~s(export FUNES_TOKEN="abc")
      assert script =~ ~s(export FUNES_THREAD="42")
      # exec replaces the shell with the harness — the window IS the session, not a subshell
      assert script =~ "exec pi"
    end

    test "the launcher is taken verbatim (a machine-local command, e.g. a claude wrapper)" do
      [_, _, _, _, _, _, script] = Spawn.command("export FUNES_THREAD=\"7\"", "claude --mcp-config /x")
      assert script =~ "exec claude --mcp-config /x"
    end
  end
end
