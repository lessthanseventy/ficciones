defmodule Funes.World do
  @moduledoc """
  A world (worlds/orbis Slice 1): a first-class composition — a git-tracked scope
  (`paths`), a `roster` of archetype instances, and free-form `knobs` — that aleph
  reads to drive its picker/survey/spawn. Compositions are DATA (this table),
  capabilities are nix (the archetype templates); disjoint, so the two never conflict.

  `type` (code|life|blank) and `scope` (project|machine) are closed sets the DB
  CHECKs guard (§10) — the schema does not mirror them, a bad value raises at insert.
  `paths`/`roster`/`knobs` are JSON columns (`Funes.JSONColumn`): a list, a list of
  maps, and a map respectively.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "world" do
    field :name, :string
    field :type, :string
    field :scope, :string
    field :paths, Funes.JSONColumn
    field :roster, Funes.JSONColumn
    field :knobs, Funes.JSONColumn
    field :created_at, :utc_datetime
  end

  @mutable [:type, :scope, :paths, :roster, :knobs]

  @doc """
  Register a world. `name` is required and unique (DB); `type`/`scope` are the DB's
  own closed-set guards (§10), so a bad value raises at insert rather than being
  re-checked here. Stamps `created_at`, matching the fact schema's second-truncated
  UTC.
  """
  def register_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name | @mutable])
    |> validate_required([:name])
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Edit a world's mutable fields (`type`/`scope`/`paths`/`roster`/`knobs`). `name` and
  `created_at` are immutable — a world's identity and birth are not re-cast here.
  """
  def edit_changeset(%__MODULE__{} = world, attrs) do
    cast(world, attrs, @mutable)
  end
end
