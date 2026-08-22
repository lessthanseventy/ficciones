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
end
