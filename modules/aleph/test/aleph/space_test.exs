defmodule Aleph.SpaceTest do
  @moduledoc """
  Aleph.Space.all/0 + next/prev — the picker order after the Slice 0 collapse. Sessions is deleted;
  only Orbis (the god-view survey) and Tlön (World #1) remain, and Tab cycles between the two.
  """
  use ExUnit.Case, async: true

  alias Aleph.Panel.Activity
  alias Aleph.Panel.Health
  alias Aleph.Panel.Leaves
  alias Aleph.Panel.Memory
  alias Aleph.Panel.Pulse
  alias Aleph.Panel.Stack
  alias Aleph.Panel.Terminal
  alias Aleph.Panel.WindowBar
  alias Aleph.Space

  # The seeded Tlön world, aleph-shaped (Aleph.Worlds.all/0 output — string-keyed roster from JSON).
  @tlon %{
    name: "Tlön",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
  }

  test "the picker offers exactly Orbis and Tlön; Sessions is gone" do
    # Space.all/0 reads the live Aleph.Worlds cache (funes down under test → []), so this exercises
    # the hardcoded-Tlön FALLBACK — proving aleph never boots without a World.
    assert Enum.map(Space.all(), & &1.key) == [:orbis, :tlon]
  end

  test "Tab from Orbis lands on Tlön (no Sessions in between)" do
    assert Space.next(:orbis).key == :tlon
    assert Space.next(:tlon).key == :orbis
  end

  describe "all/1 (derived from funes worlds)" do
    test "one seeded Tlön world → picker is exactly [:orbis, :tlon]" do
      assert Enum.map(Space.all([@tlon]), & &1.key) == [:orbis, :tlon]
    end

    test "the derived Tlön space matches the Slice-0 hardcoded surface/coworker/left/right" do
      tlon = Enum.find(Space.all([@tlon]), &(&1.key == :tlon))

      assert tlon.label == "Tlön"
      assert tlon.surface == [WindowBar, {Terminal, :machine}, Pulse]
      assert tlon.left == [Stack, Memory]
      assert tlon.right == [Health, Activity, Leaves]
      # The roster lead's name (string-keyed JSON) becomes the center coworker.
      assert tlon.coworker == "tertius"
    end

    test "empty worlds → hardcoded-Tlön fallback still yields [:orbis, :tlon]" do
      assert Enum.map(Space.all([]), & &1.key) == [:orbis, :tlon]
    end

    test "two worlds → [:orbis, :tlon, <second key>], keyed by name slug" do
      freedonia = %{@tlon | name: "Freedonia", roster: [%{"archetype" => "surveyor", "name" => "rufus"}]}

      spaces = Space.all([@tlon, freedonia])
      assert Enum.map(spaces, & &1.key) == [:orbis, :tlon, :freedonia]

      second = Enum.find(spaces, &(&1.key == :freedonia))
      assert second.label == "Freedonia"
      assert second.coworker == "rufus"
    end

    test "the name→key slug transliterates ö→o so \"Tlön\" keys as :tlon exactly" do
      assert Enum.any?(Space.all([@tlon]), &(&1.key == :tlon))
    end

    test "a roster with atom keys still yields the lead coworker (defensive)" do
      atomish = %{@tlon | roster: [%{archetype: "surveyor", name: "tertius"}]}
      tlon = Enum.find(Space.all([atomish]), &(&1.key == :tlon))
      assert tlon.coworker == "tertius"
    end
  end
end
