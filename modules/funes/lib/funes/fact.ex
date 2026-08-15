defmodule Funes.Fact do
  @moduledoc """
  A durable thing learned (spec §4): the ledger's successor, the judgement a system
  cannot derive. One row is one claim with one `provenance` — `stated` (the owner
  said it, verbatim) or `derived` (we produced it) — and reproducibility rides a
  separate axis, `check_cmd`, the command that re-runs the claim. `kind` and
  `provenance` are closed sets the DB CHECKs; the schema does not mirror them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "fact" do
    field :kind, :string
    field :text, :string
    field :provenance, :string
    field :check_cmd, :string
    field :incident, :string
    field :taught, :string
    field :supersedes, :id
    field :created_at, :utc_datetime
    belongs_to :thread, Funes.Thread
    belongs_to :source_session, Funes.Session
  end

  @doc """
  Bank a fact. `kind`, `text`, and `provenance` are required; the closed sets on
  `kind`/`provenance` and the FKs on `thread`/`supersedes`/`source_session` are the
  DB's own guards (§10) — a bad value raises rather than being re-checked here.
  """
  def bank_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :thread_id,
      :kind,
      :text,
      :provenance,
      :check_cmd,
      :incident,
      :taught,
      :supersedes,
      :source_session_id
    ])
    |> validate_required([:kind, :text, :provenance])
    |> put_change(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
