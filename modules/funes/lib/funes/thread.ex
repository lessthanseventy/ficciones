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
    field :scope, :string, default: "project"
    field :created_at, :utc_datetime
    # A thread has 0..1 agent (aleph §3), staffed via Funes.Staff. Nullable FK;
    # the assignment reference lives on the thread.
    belongs_to :agent, Funes.Agent
  end

  @doc ~s{A new thread, opened now. Title is required; state is not caller-settable. `scope`
  defaults to `"project"`; the Tlön machine-coworker path opens with `"machine"` so the
  project surfaces (chorus / open_threads) can filter it out — see the thread_scope migration.}
  def open_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:title, :scope])
    |> validate_required([:title])
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
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
