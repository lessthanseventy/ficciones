defmodule Aleph.CrewTest do
  use ExUnit.Case, async: true

  alias Aleph.Crew

  describe "roles/0 and role/1" do
    test "reviewer is a known role with its handle, window prefix, and profile" do
      assert %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"} =
               Crew.role("reviewer")
    end

    test "an unknown role is nil" do
      assert Crew.role("nope") == nil
    end

    test "roles/0 lists the MVP crew" do
      assert Crew.roles() |> Map.keys() |> Enum.sort() == ["reviewer"]
    end
  end

  describe "crew_window/2" do
    test "names a per-thread window from role prefix + thread id" do
      assert Crew.crew_window("reviewer", 42) == "r42"
    end

    test "accepts a string thread id" do
      assert Crew.crew_window("reviewer", "42") == "r42"
    end

    test "unknown role raises (a caller must pass a real role)" do
      assert_raise ArgumentError, fn -> Crew.crew_window("planner", 42) end
    end
  end

  describe "handle_role/1 (reverse: a funes handle → its role key)" do
    test "resolves the reviewer handle" do
      assert Crew.handle_role("reviewer-machine") == "reviewer"
    end

    test "a non-crew handle is nil" do
      assert Crew.handle_role("claude-machine") == nil
    end
  end

  describe "spawn_argv/3 and boot_script/2 (pure tmux builders)" do
    test "spawn_argv targets the tlon session on the aleph-tertius socket, window r<id>, detached" do
      argv = Crew.spawn_argv("reviewer", 42, "boot-script-here")

      assert argv == [
               "-L",
               "aleph-tertius",
               "new-window",
               "-d",
               "-t",
               "tlon",
               "-n",
               "r42",
               "boot-script-here"
             ]
    end

    test "boot_script sources the funes exports then execs the reviewer profile launcher" do
      script = Crew.boot_script("export FUNES_THREAD=\"42\"", "tmux -L aleph-reviewer … 'pi …'")
      assert script =~ "export TERM=xterm-256color"
      assert script =~ "export FUNES_THREAD=\"42\""
      assert String.contains?(script, "\nexec tmux -L aleph-reviewer")
    end

    test "kill_argv removes the role's window on the same server" do
      assert Crew.kill_argv("reviewer", 42) ==
               ["-L", "aleph-tertius", "kill-window", "-t", "tlon:r42"]
    end
  end
end
