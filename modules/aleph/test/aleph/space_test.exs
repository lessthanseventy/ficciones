defmodule Aleph.SpaceTest do
  @moduledoc """
  Aleph.Space.all/0 + next/prev — the picker order after the Slice 0 collapse. Sessions is deleted;
  only Orbis (the god-view survey) and Tlön (World #1) remain, and Tab cycles between the two.
  """
  use ExUnit.Case, async: true

  alias Aleph.Space

  test "the picker offers exactly Orbis and Tlön; Sessions is gone" do
    assert Enum.map(Space.all(), & &1.key) == [:orbis, :tlon]
  end

  test "Tab from Orbis lands on Tlön (no Sessions in between)" do
    assert Space.next(:orbis).key == :tlon
    assert Space.next(:tlon).key == :orbis
  end
end
