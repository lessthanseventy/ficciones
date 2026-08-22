defmodule Funes.WorldTest do
  # `Funes.World` schema + changesets (worlds/orbis Slice 1). The DB is the guard
  # (§10): the closed sets on `type`/`scope` raise at insert, never re-checked here.
  # JSON columns round-trip through SQLite, so assertions read back through the DB.
  use ExUnit.Case, async: false

  alias Funes.Repo
  alias Funes.World

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  describe "register_changeset/1" do
    test "a valid world inserts and its JSON columns round-trip through SQLite" do
      {:ok, world} =
        %{
          name: "Tlön",
          type: "code",
          scope: "machine",
          paths: ["modules/*"],
          roster: [%{"archetype" => "surveyor", "name" => "tertius"}],
          knobs: %{"accent" => "cyan"}
        }
        |> World.register_changeset()
        |> Repo.insert()

      reloaded = Repo.get!(World, world.id)
      assert reloaded.name == "Tlön"
      assert reloaded.type == "code"
      assert reloaded.scope == "machine"
      assert reloaded.paths == ["modules/*"]
      assert reloaded.roster == [%{"archetype" => "surveyor", "name" => "tertius"}]
      assert reloaded.knobs == %{"accent" => "cyan"}
      assert %DateTime{} = reloaded.created_at
    end

    test "defaults type/scope/paths/roster/knobs at the DB when omitted" do
      {:ok, world} =
        %{name: "Bare"} |> World.register_changeset() |> Repo.insert()

      reloaded = Repo.get!(World, world.id)
      assert reloaded.type == "code"
      assert reloaded.scope == "machine"
      assert reloaded.paths == []
      assert reloaded.roster == []
      assert reloaded.knobs == %{}
    end

    test "name is required" do
      refute World.register_changeset(%{type: "code"}).valid?
    end

    test "an invalid type raises at the DB (the CHECK is the guard, not the changeset)" do
      cs = World.register_changeset(%{name: "Bogus", type: "planet"})
      assert cs.valid?
      assert_raise Ecto.ConstraintError, fn -> Repo.insert(cs) end
    end
  end

  describe "edit_changeset/2" do
    setup do
      {:ok, world} =
        %{name: "Tlön", paths: ["a"]} |> World.register_changeset() |> Repo.insert()

      %{world: world}
    end

    test "casts mutable fields but not name/created_at", %{world: world} do
      cs = World.edit_changeset(world, %{name: "Renamed", paths: ["b"], knobs: %{"k" => 1}})

      refute Ecto.Changeset.get_change(cs, :name)
      refute Ecto.Changeset.get_change(cs, :created_at)
      assert Ecto.Changeset.get_change(cs, :paths) == ["b"]
      assert Ecto.Changeset.get_change(cs, :knobs) == %{"k" => 1}
    end
  end
end
