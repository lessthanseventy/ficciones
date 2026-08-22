defmodule Aleph.SpaceTest do
  @moduledoc """
  Aleph.Space.all/0 + next/prev — the picker order after the Slice 0 collapse. Sessions is deleted;
  only Orbis (the god-view survey) and one World space remain, and Tab cycles between the two.

  Phase C1.2: World spaces are keyed by their funes id (not a name slug), so id-keying is exercised
  throughout — the fixture `@tlon` carries `id: 1` and the fallback (funes down / no worlds) keys as
  the sentinel `0`.
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
    id: 1,
    name: "Tlön",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
  }

  test "the picker offers exactly Orbis and the fallback World; Sessions is gone" do
    # Space.all/0 reads the live Aleph.Worlds cache (funes down under test → []), so this exercises
    # the hardcoded-Tlön FALLBACK, keyed as the sentinel 0 — proving aleph never boots without a
    # World.
    assert Enum.map(Space.all(), & &1.key) == [:orbis, 0]
  end

  test "Tab from Orbis lands on the fallback World (no Sessions in between)" do
    assert Space.next(:orbis).key == 0
    assert Space.next(0).key == :orbis
  end

  describe "all/1 (derived from funes worlds)" do
    test "one seeded Tlön world → picker is exactly [:orbis, 1]" do
      assert Enum.map(Space.all([@tlon]), & &1.key) == [:orbis, 1]
    end

    test "the derived Tlön space matches the Slice-0 hardcoded surface/coworker/left/right" do
      tlon = Enum.find(Space.all([@tlon]), &(&1.key == 1))

      assert tlon.id == 1
      assert tlon.label == "Tlön"
      assert tlon.surface == [WindowBar, {Terminal, :machine}, Pulse]
      assert tlon.left == [Stack, Memory]
      assert tlon.right == [Health, Activity, Leaves]
      # The roster lead's name (string-keyed JSON) becomes the center coworker.
      assert tlon.coworker == "tertius"
      # The full roster rides along too (C2/C3 read it), not just the derived coworker name.
      assert tlon.roster == @tlon.roster
    end

    test "empty worlds → hardcoded-Tlön fallback still yields [:orbis, 0]" do
      assert Enum.map(Space.all([]), & &1.key) == [:orbis, 0]
    end

    test "two worlds → [:orbis, 1, 2], keyed by funes id" do
      freedonia = %{@tlon | id: 2, name: "Freedonia", roster: [%{"archetype" => "surveyor", "name" => "rufus"}]}

      spaces = Space.all([@tlon, freedonia])
      assert Enum.map(spaces, & &1.key) == [:orbis, 1, 2]

      second = Enum.find(spaces, &(&1.key == 2))
      assert second.id == 2
      assert second.label == "Freedonia"
      assert second.coworker == "rufus"
    end

    test "a world space is keyed by its funes id" do
      spaces =
        Space.all([
          %{id: 7, name: "Tlön", roster: [%{"name" => "tertius"}], type: "code", paths: [], scope: "machine"}
        ])

      assert [%{key: :orbis}, %{key: 7, label: "Tlön", id: 7}] = spaces
    end

    test "a roster with atom keys still yields the lead coworker (defensive)" do
      atomish = %{@tlon | roster: [%{archetype: "surveyor", name: "tertius"}]}
      tlon = Enum.find(Space.all([atomish]), &(&1.key == 1))
      assert tlon.coworker == "tertius"
    end
  end

  describe "the funes-down fallback" do
    test "keys as the sentinel 0 (real funes ids start at 1)" do
      assert [%{key: :orbis}, %{key: 0, label: "Tlön"}] = Aleph.Space.all([])
    end
  end

  describe "fetch/2 (pure, over an explicit spaces list)" do
    test "returns the matching space" do
      spaces = Space.all([@tlon])
      assert Space.fetch(:orbis, spaces).key == :orbis
      assert Space.fetch(1, spaces).key == 1
    end

    test "returns nil on a missing key (no silent Orbis default)" do
      assert Space.fetch(999, Space.all([@tlon])) == nil
    end
  end

  describe "fetch/1 (reads the live cache)" do
    test "returns nil on a missing key" do
      assert Space.fetch(999) == nil
    end
  end

  describe "world?/1" do
    test "is the mode predicate distinguishing Orbis from World keys" do
      refute Space.world?(:orbis)
      assert Space.world?(1)
      assert Space.world?(0)
    end
  end
end
