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
    # Workline state (slice 1) — all nil on a plain thread. `stage` is the machine's position,
    # `slug` names `work/<slug>/`, `born` who authored the intent, `awaiting` the parked gate.
    field :stage, :string
    field :slug, :string
    field :born, :string
    field :awaiting, :string
    belongs_to :world, Funes.World
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

  @doc ~s{A new WORKLINE thread (slice 1): opens at stage "intent", machine-scoped by default
  (worklines are machine work — the root machine thread stays oldest, so leaf ordering holds).
  `born` defaults to "operator"; the Maintain back-edge opens with "machine" and gates.}
  def workline_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:title, :scope, :slug, :born, :world_id])
    |> validate_required([:title, :slug])
    |> validate_inclusion(:born, ["operator", "machine"])
    |> put_new_change(:born, "operator")
    |> put_new_change(:scope, "machine")
    |> put_change(:stage, "intent")
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Flip workline machinery — `stage` and/or `awaiting` — on an existing thread."
  def workline_stage_changeset(thread, changes) do
    change(thread, Map.take(changes, [:stage, :awaiting]))
  end

  defp put_new_change(changeset, key, value) do
    case fetch_change(changeset, key) do
      {:ok, _present} -> changeset
      :error -> put_change(changeset, key, value)
    end
  end
end
