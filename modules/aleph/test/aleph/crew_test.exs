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
end
