defmodule Funes.Worlds do
  @moduledoc """
  The worlds context (worlds/orbis Slice 1): the write pipe and reads over the
  `world` table. Compositions are DATA here; aleph reads `all/0` to drive its
  picker/survey/spawn, and every write announces on `Funes.Bus`'s worlds topic so
  those live surfaces refresh. A world is machine-global — no thread scope.
  """
  import Ecto.Query

  alias Funes.Bus
  alias Funes.Repo
  alias Funes.World

  @doc "Register a world. `{:ok, world}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register(attrs) do
    attrs |> World.register_changeset() |> Repo.insert() |> Bus.announce(:world_registered)
  end

  @doc "Every world, newest-first (by id) — the read aleph's Orbis survey/picker maps over."
  def all do
    Repo.all(from w in World, order_by: [desc: w.id])
  end

  @doc "A world by id, or nil."
  def get(id), do: Repo.get(World, id)

  @doc "A world by its unique name, or nil — the find-or-create + seed lookup."
  def by_name(name), do: Repo.get_by(World, name: name)

  @doc "Edit a world's mutable fields. `{:ok, world}` or `{:error, changeset}`."
  def edit(%World{} = world, attrs) do
    world |> World.edit_changeset(attrs) |> Repo.update() |> Bus.announce(:world_edited)
  end

  @doc "Remove a world. `{:ok, world}` or `{:error, changeset}`."
  def remove(%World{} = world) do
    world |> Repo.delete() |> Bus.announce(:world_removed)
  end
end
