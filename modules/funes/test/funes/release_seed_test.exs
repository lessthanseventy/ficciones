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
    assert world.roster == [%{"archetype" => "surveyor", "name" => "tertius"}]
  end

  test "is idempotent — called twice yields exactly one Tlön row" do
    Release.do_seed_world()
    Release.do_seed_world()

    tlons = Enum.filter(Worlds.all(), &(&1.name == "Tlön"))
    assert length(tlons) == 1
  end
end
