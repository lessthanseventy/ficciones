defmodule Aleph.OrbisTest do
  # The rollup DATA semantics (Orbis Tertius slice 2): the pure status + tally rules shared by the
  # Tlön sidebar panel and the chat-tab strip. `rollup/0` itself reads funes (exercised live, not
  # here, like the cockpit reads); these pin the pure rules so the two surfaces can never drift.
  use ExUnit.Case, async: true

  alias Aleph.Orbis

  describe "status/2" do
    test "a closed thread is done, regardless of conflicts" do
      assert Orbis.status("closed", 0) == :done
      assert Orbis.status("closed", 3) == :done
    end

    test "an open thread with a blocker or failed check is stalled" do
      assert Orbis.status("open", 1) == :stalled
    end

    test "an open thread with a clean board is open" do
      assert Orbis.status("open", 0) == :open
    end
  end

  describe "summarize/1" do
    test "tallies each bucket and sums conflicts across rows" do
      rows = [
        %{status: :stalled, conflicts: 2},
        %{status: :open, conflicts: 0},
        %{status: :open, conflicts: 0},
        %{status: :done, conflicts: 0}
      ]

      assert Orbis.summarize(rows) == %{open: 2, stalled: 1, done: 1, conflicts: 2}
    end

    test "an empty list is all zeros" do
      assert Orbis.summarize([]) == %{open: 0, stalled: 0, done: 0, conflicts: 0}
    end
  end
end
