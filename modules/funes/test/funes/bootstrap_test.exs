defmodule Funes.BootstrapTest do
  # Reshape slice A: boot-time integrity — the default workspace creates itself,
  # and no thread points at a workspace that isn't there (the live db carried a
  # thread → world_id=5 with only world 1 existing; remove_world orphaned it).
  use ExUnit.Case, async: false

  alias Funes.Bootstrap
  alias Funes.Channel
  alias Funes.Repo
  alias Funes.Thread
  alias Funes.Worlds

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  test "an empty world table seeds the default workspace" do
    assert {:ok, world} = Bootstrap.ensure()
    assert world.name == "ficciones"
    assert world.scope == "machine"
    assert Enum.map(world.roster, & &1["name"]) == ["tertius", "hronir"]
    assert [%{id: id}] = Worlds.all()
    assert id == world.id
  end

  test "an existing world is left untouched — no second seed, name preserved" do
    {:ok, tlon} = Worlds.register(%{name: "Tlön", type: "code", scope: "machine", paths: [], roster: []})

    assert {:ok, world} = Bootstrap.ensure()
    assert world.id == tlon.id
    assert world.name == "Tlön"
    assert length(Worlds.all()) == 1
  end

  test "threads with no workspace are repaired to the default" do
    {:ok, thread} = Channel.open_thread(%{title: "adrift"})
    assert thread.world_id == nil

    {:ok, world} = Bootstrap.ensure()
    assert Repo.get(Thread, thread.id).world_id == world.id
  end

  test "threads pointing at a dead workspace are repaired to the default" do
    {:ok, world} = Bootstrap.ensure()
    {:ok, thread} = Channel.open_thread(%{title: "orphan"})
    # The live-db drift this repairs was born under a suspended FK pragma (table
    # rebuilds, pre-integrity removes); reproduce it the same way. pool_size is 1
    # in test, so the pragma toggles the one real connection.
    Repo.query!("PRAGMA foreign_keys = OFF")
    Repo.query!("UPDATE thread SET world_id = 999 WHERE id = ?", [thread.id])
    Repo.query!("PRAGMA foreign_keys = ON")

    assert {:ok, %{id: world_id}} = Bootstrap.ensure()
    assert world_id == world.id
    assert Repo.get(Thread, thread.id).world_id == world.id
  end

  test "threads in a live non-default workspace are untouched" do
    {:ok, _default} = Bootstrap.ensure()
    {:ok, other} = Worlds.register(%{name: "other", type: "code", scope: "project", paths: [], roster: []})
    {:ok, thread} = Channel.open_thread(%{title: "housed"})
    Repo.update_all(Thread, set: [world_id: other.id])

    assert {:ok, _} = Bootstrap.ensure()
    assert Repo.get(Thread, thread.id).world_id == other.id
  end

  test "ensure_safe on a healthy schema behaves like ensure" do
    assert {:ok, %Funes.World{}} = Bootstrap.ensure_safe()
  end
end
