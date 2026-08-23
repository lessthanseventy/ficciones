defmodule Aleph.MachineChat.StaffingTest do
  @moduledoc """
  The pure pick for who gets staffed as a new chat thread's lead: the composer text's first
  @-mentioned coworker, else the configured default. Pulled out of `Loop` (which grabs the TTY)
  so it tests without one.
  """
  use ExUnit.Case, async: true

  alias Aleph.MachineChat.Staffing

  @roster [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}]

  test "the first @-mentioned coworker wins over the default" do
    assert Staffing.pick_coworker("@tertius-machine do x", "hronir-machine", @roster) == "tertius-machine"
  end

  test "no mention falls back to the default" do
    assert Staffing.pick_coworker("no mention", "hronir-machine", @roster) == "hronir-machine"
  end

  test "a non-coworker @-handle is ignored — falls back to the default" do
    assert Staffing.pick_coworker("@andrew hi", "hronir-machine", @roster) == "hronir-machine"
  end

  test "an empty roster (funes-down) falls back to the default even with a mention" do
    assert Staffing.pick_coworker("@tertius-machine do x", "hronir-machine") == "hronir-machine"
  end

  describe "default_coworker/1 — the roster-derived default (no @-mention path)" do
    # The regression seam: the machine-chat beam has no `Aleph.Worlds` cache, so it must derive the
    # default from the LIVE funes roster. Given the live Tlön cast (a lone surveyor), the default
    # MUST be that entry's registered handle — never a builder from a stale stand-in whose
    # `-machine` handle was never registered as a funes agent (the leaderless-thread silence bug).
    test "picks the roster's builder as its -machine handle" do
      assert Staffing.default_coworker(@roster) == "hronir-machine"
    end

    test "a builder-less roster (the live Tlön cast) picks its lead, not a stand-in builder" do
      assert Staffing.default_coworker([%{"archetype" => "surveyor", "name" => "tertius"}]) ==
               "tertius-machine"
    end

    test "an empty roster yields nil — never a guessed handle that was never registered" do
      assert Staffing.default_coworker([]) == nil
    end
  end
end
