defmodule Aleph.MachineChat.StaffingTest do
  @moduledoc """
  The pure pick for who gets staffed as a new chat thread's lead: the composer text's first
  @-mentioned coworker, else the configured default. Pulled out of `Loop` (which grabs the TTY)
  so it tests without one.
  """
  use ExUnit.Case, async: true

  alias Aleph.MachineChat.Staffing

  test "the first @-mentioned coworker wins over the default" do
    assert Staffing.pick_coworker("@pi-machine do x", "claude-machine") == "pi-machine"
  end

  test "no mention falls back to the default" do
    assert Staffing.pick_coworker("no mention", "claude-machine") == "claude-machine"
  end

  test "a non-coworker @-handle is ignored — falls back to the default" do
    assert Staffing.pick_coworker("@andrew hi", "claude-machine") == "claude-machine"
  end
end
