defmodule Funes.Event do
  @moduledoc """
  Append-only, what happened (spec §4). One table with a closed `kind` the DB
  CHECKs — the mechanism kinds plus the one outcome kind, `work_landed`, that
  answers "what did I do yesterday" (§9.4). `correlation` is the explicit id of the
  lifecycle a row belongs to; `detail` is JSON for a human to read, never queried.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "event" do
    field :kind, :string
    field :correlation, :string
    field :detail, Funes.JSONColumn
    field :created_at, :utc_datetime
    belongs_to :thread, Funes.Thread
  end

  @doc """
  Record an event. `kind` is required and the closed set is the DB's own CHECK
  (§10) — a kind outside it raises, never re-checked here.
  """
  def record_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :kind, :correlation, :detail])
    |> validate_required([:kind])
    |> put_change(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
