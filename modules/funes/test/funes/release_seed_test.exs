defmodule Funes.ReleaseSeedTest do
  # `Funes.Release.seed_world/0` — the flake's ExecStartPre find-or-create for the
  # Tlön world row (worlds/orbis Slice 1). The DB work lives in `do_seed_world/0` so
  # the test drives it against the already-running test repo (no release double-boot).
  use ExUnit.Case, async: false

  alias Funes.Release
  alias Funes.Worlds

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  test "seeds the Tlön world with the right fields when absent" do
    assert Worlds.by_name("Tlön") == nil

    {:ok, world} = Release.do_seed_world()

    assert world.name == "Tlön"
    assert world.type == "code"
    assert world.scope == "machine"
    assert world.paths == ["modules/*"]

    assert world.roster == [
             %{"archetype" => "surveyor", "name" => "tertius"},
             %{"archetype" => "builder", "name" => "hronir"}
           ]
  end

  test "is idempotent — called twice yields exactly one Tlön row with no roster dupes" do
    Release.do_seed_world()
    Release.do_seed_world()

    tlons = Enum.filter(Worlds.all(), &(&1.name == "Tlön"))
    assert length(tlons) == 1

    assert hd(tlons).roster == [
             %{"archetype" => "surveyor", "name" => "tertius"},
             %{"archetype" => "builder", "name" => "hronir"}
           ]
  end

  test "backfill upgrades a legacy single-surveyor row to add the builder" do
    {:ok, legacy} =
      Worlds.register(%{
        name: "Tlön",
        type: "code",
        scope: "machine",
        paths: ["modules/*"],
        roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
      })

    assert legacy.roster == [%{"archetype" => "surveyor", "name" => "tertius"}]

    {:ok, upgraded} = Release.do_seed_world()

    assert upgraded.id == legacy.id

    assert upgraded.roster == [
             %{"archetype" => "surveyor", "name" => "tertius"},
             %{"archetype" => "builder", "name" => "hronir"}
           ]
  end

  test "a hand-edited roster is left alone" do
    {:ok, edited} =
      Worlds.register(%{
        name: "Tlön",
        type: "code",
        scope: "machine",
        paths: ["modules/*"],
        roster: [
          %{"archetype" => "surveyor", "name" => "tertius"},
          %{"archetype" => "planner", "name" => "borges"}
        ]
      })

    result = Release.do_seed_world()

    assert result.id == edited.id
    assert result.roster == edited.roster

    assert Worlds.by_name("Tlön").roster == [
             %{"archetype" => "surveyor", "name" => "tertius"},
             %{"archetype" => "planner", "name" => "borges"}
           ]
  end
end
