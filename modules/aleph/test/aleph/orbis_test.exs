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

  describe "worlds/1" do
    # rollup/0 wraps its per-thread rows under a single hardcoded world (Slice 0, funes down under
    # test). rollup/0 itself reads funes (exercised live, like the cockpit reads); this pins the
    # pure grouping it delegates to, so the survey face's world shape can never drift.
    test "groups the rollup rows under one hardcoded world (Tlön, id 0), carrying summary + leaves" do
      rows = [
        %{status: :open, conflicts: 0},
        %{status: :stalled, conflicts: 2},
        %{status: :done, conflicts: 0}
      ]

      assert [%{id: 0, name: "Tlön", summary: summary, leaves: ^rows}] = Orbis.worlds(rows)
      assert summary == %{open: 1, stalled: 1, done: 1, conflicts: 2}
    end

    test "an empty board is still one world, with a zeroed summary and no leaves" do
      assert [%{id: 0, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}] =
               Orbis.worlds([])
    end
  end

  describe "worlds/2 (grouped by real world refs — D0.3: every row carries its funes id)" do
    # worlds/1 reads the live Aleph.Worlds cache (funes down under test → [] → literal "Tlön"
    # fallback, covered above). worlds/2 is the pure grouping it delegates to, tested with
    # injected `%{id, name}` refs so a real funes world's id/name drives the survey row.
    test "one world → the rollup rows group under that world's real id + name" do
      rows = [%{status: :open, conflicts: 0}, %{status: :stalled, conflicts: 1}]

      assert [%{id: 7, name: "Freedonia", summary: summary, leaves: ^rows}] =
               Orbis.worlds(rows, [%{id: 7, name: "Freedonia"}])

      assert summary == %{open: 1, stalled: 1, done: 0, conflicts: 1}
    end

    test "a second world gets a zeroed row, still carrying its OWN id (coarse leaf attribution)" do
      rows = [%{status: :open, conflicts: 0}]

      assert [%{id: 1, name: "Freedonia"}, %{id: 2, name: "Ruritania", summary: summary, leaves: []}] =
               Orbis.worlds(rows, [%{id: 1, name: "Freedonia"}, %{id: 2, name: "Ruritania"}])

      assert summary == %{open: 0, stalled: 0, done: 0, conflicts: 0}
    end

    test "no world refs → the literal \"Tlön\" (id 0) fallback so the survey never breaks" do
      rows = [%{status: :open, conflicts: 0}]
      assert [%{id: 0, name: "Tlön", leaves: ^rows}] = Orbis.worlds(rows, [])
    end
  end
end
