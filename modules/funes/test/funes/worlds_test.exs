defmodule Funes.WorldsTest do
  # The `Funes.Worlds` context (worlds/orbis Slice 1): the write pipe
  # (changeset |> insert |> Bus.announce) and the reads aleph drives its
  # picker/survey from. The DB is the bus (§10): assertions read back through it.
  use ExUnit.Case, async: false

  alias Funes.Bus
  alias Funes.World
  alias Funes.Worlds

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  describe "register/1" do
    test "inserts and announces on the worlds topic" do
      Bus.subscribe_worlds()

      {:ok, world} =
        Worlds.register(%{name: "Tlön", type: "code", paths: ["modules/*"]})

      assert %World{} = world
      assert world.name == "Tlön"
      assert_receive {:world_registered, %World{name: "Tlön"}}
    end

    test "a duplicate name returns {:error, changeset}, not a crash" do
      {:ok, _} = Worlds.register(%{name: "Tlön"})
      assert {:error, %Ecto.Changeset{}} = Worlds.register(%{name: "Tlön"})
    end
  end

  describe "all/0" do
    test "lists worlds newest-first" do
      {:ok, _a} = Worlds.register(%{name: "First"})
      {:ok, _b} = Worlds.register(%{name: "Second"})

      assert ["Second", "First"] == Enum.map(Worlds.all(), & &1.name)
    end
  end

  describe "get/1 and by_name/1" do
    test "return the world, or nil when absent" do
      {:ok, world} = Worlds.register(%{name: "Tlön"})

      assert Worlds.get(world.id).name == "Tlön"
      assert Worlds.by_name("Tlön").id == world.id
      assert Worlds.get(-1) == nil
      assert Worlds.by_name("nope") == nil
    end
  end

  describe "edit/2" do
    test "updates mutable fields and announces" do
      Bus.subscribe_worlds()
      {:ok, world} = Worlds.register(%{name: "Tlön", paths: ["a"]})

      {:ok, edited} = Worlds.edit(world, %{paths: ["b"], knobs: %{"accent" => "cyan"}})

      assert edited.paths == ["b"]
      assert Worlds.get(world.id).knobs == %{"accent" => "cyan"}
      assert_receive {:world_edited, %World{}}
    end
  end

  describe "remove/1" do
    test "deletes the world, rehouses its threads in the oldest remaining, announces" do
      Bus.subscribe_worlds()
      {:ok, keep} = Worlds.register(%{name: "keep"})
      {:ok, doomed} = Worlds.register(%{name: "doomed"})
      {:ok, thread} = Funes.Channel.open_thread(%{title: "tenant"})
      Funes.Repo.update_all(Funes.Thread, set: [world_id: doomed.id])

      {:ok, _} = Worlds.remove(doomed)

      assert Worlds.get(doomed.id) == nil
      assert Funes.Repo.get(Funes.Thread, thread.id).world_id == keep.id
      assert_receive {:world_removed, %World{}}
    end

    test "the last world is refused — threads must always have a home" do
      {:ok, only} = Worlds.register(%{name: "only"})

      assert {:error, :last_world} = Worlds.remove(only)
      assert Worlds.get(only.id)
    end
  end
end
