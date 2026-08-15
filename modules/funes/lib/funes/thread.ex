defmodule Funes.Thread do
  @moduledoc """
  The atom of work (aleph §2). A subject promoted to a first-class row; `message`
  and, later, the dossier tables (`fact`/`event`/`issue`) hang off it. Its `state`
  is a closed set the database enforces.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "thread" do
    field :title, :string
    field :state, :string, default: "open"
    field :created_at, :utc_datetime
    # A thread has 0..1 agent (aleph §3), staffed via Funes.Staff. Nullable FK;
    # the assignment reference lives on the thread, added in step 3's migration.
    belongs_to :agent, Funes.Agent
  end

  @doc "A new thread, opened now. Title is required; state is not caller-settable."
  def open_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Move a thread to a new state. The closed set (open | closed) is enforced by the
  database CHECK alone — not mirrored here, the same single-source rule the FK
  follows: an invalid state is refused by SQLite (it raises), never by a second
  guard that could drift from the DB's.
  """
  def state_changeset(thread, state) do
    change(thread, state: state)
  end
end
