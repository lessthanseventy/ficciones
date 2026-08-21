defmodule Mix.Tasks.Aleph.Crew.SpawnTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Aleph.Crew.Spawn

  test "parse/1 pulls role, thread id, and --task" do
    assert Spawn.parse(["reviewer", "42", "--task", "review HEAD~1"]) ==
             {:ok, "reviewer", 42, "review HEAD~1"}
  end

  test "a missing --task is an error" do
    assert {:error, _} = Spawn.parse(["reviewer", "42"])
  end

  test "a non-integer thread id is an error" do
    assert {:error, _} = Spawn.parse(["reviewer", "x", "--task", "t"])
  end
end

defmodule Mix.Tasks.Aleph.Crew.KillTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Aleph.Crew.Kill

  test "parse/1 pulls thread id and optional role (default reviewer)" do
    assert Kill.parse(["42"]) == {:ok, "reviewer", 42}
    assert Kill.parse(["42", "reviewer"]) == {:ok, "reviewer", 42}
  end
end
