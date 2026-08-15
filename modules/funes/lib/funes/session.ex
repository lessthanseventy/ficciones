defmodule Funes.Session do
  @moduledoc """
  The ephemeral instance of an agent (aleph §3): it runs in a pane, on an engine,
  on one thread, and it compacts and dies (§10). It references an `agent` and a
  `thread`. `workspace_ref` is §2's one seam — an OPAQUE handle to the pane, never
  a cached copy of the workspace's properties; liveness is asked of the arbiter
  live, never stored. `ended_at` is the only lifecycle stored: NULL means a
  candidate to jump into.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "session" do
    field :workspace_ref, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    belongs_to :agent, Funes.Agent
    belongs_to :thread, Funes.Thread
  end

  @doc """
  Start a session for an agent on a thread. Both references are required; the FKs
  themselves are the DB's guard (§10) — an orphan is refused by SQLite, so it
  raises rather than returning a changeset. `workspace_ref` is optional and opaque.
  """
  def start_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:agent_id, :thread_id, :workspace_ref])
    |> validate_required([:agent_id, :thread_id])
    |> put_change(:started_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc "Stamp a session ended, now. Sessions die; you brief a new one (§3b)."
  def end_changeset(session) do
    change(session, ended_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
