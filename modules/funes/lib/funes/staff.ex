defmodule Funes.Staff do
  @moduledoc """
  The staff (aleph §3b): the durable `agent` roster and the ephemeral `session`s
  that run them, plus staffing a thread with an agent. This context owns the
  agent/session data model and assignment; `Funes.Channel` keeps owning
  thread/message.

  Deliberately out of scope, and deferred (§3b/§10): presence ("clocked out" is
  derived from the engine, asked live), routing/cover, the night shift, engine
  resolution, and the PubSub wake. This step builds only the model those layers
  will stand on — the recipient identity step 2's wake was waiting for.
  """
  import Ecto.Query
  alias Funes.{Agent, Repo, Session, Thread}

  @doc "Register a durable agent. `{:ok, agent}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register_agent(attrs) do
    attrs |> Agent.register_changeset() |> Repo.insert()
  end

  @doc "The durable agent with this name, or nil. Names are unique (§5b)."
  def agent_by_name(name) do
    Repo.get_by(Agent, name: name)
  end

  @doc """
  Staff a thread with an agent (a thread has 0..1 agent, §3). Assigning again
  replaces the previous agent. Takes a persisted `%Agent{}`, so the FK cannot fire
  here — it is the DB's guard against a raw write of a bogus agent_id (§10).
  """
  def assign(%Thread{} = thread, %Agent{} = agent) do
    thread
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:agent_id, agent.id)
    |> Repo.update()
    |> Funes.Bus.announce(:thread_assigned)
  end

  @doc "Clear a thread's agent back to unassigned."
  def unassign(%Thread{} = thread) do
    # force_change, not change: the caller's struct may hold a stale agent_id (it is
    # not reloaded after assign), and change/2 would emit a no-op if the in-memory
    # value already matched. The write must be unconditional.
    thread
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:agent_id, nil)
    |> Repo.update()
  end

  @doc "The threads an agent is staffed on (an agent maps to many threads, §3), newest first."
  def threads_for(%Agent{} = agent) do
    Repo.all(from t in Thread, where: t.agent_id == ^agent.id, order_by: [desc: t.id])
  end

  @doc """
  Start a session — an agent running on a thread in a pane. Returns `{:ok, session}`
  or `{:error, changeset}` on a missing agent/thread; a non-existent agent or
  thread is refused by SQLite's FK and raises (§10).
  """
  def start_session(attrs) do
    attrs |> Session.start_changeset() |> Repo.insert() |> Funes.Bus.announce(:session_started)
  end

  @doc "End a session — stamp `ended_at`. Sessions die; you brief a new one (§3b)."
  def end_session(%Session{} = session) do
    session |> Session.end_changeset() |> Repo.update() |> Funes.Bus.announce(:session_ended)
  end

  @doc """
  The session to jump into for a thread (§9.3): the newest not-yet-ended session,
  or nil if every session has ended. This hands over which pane to poke — liveness
  itself is asked of the arbiter live (§2), never read from here.
  """
  def session_for_thread(%Thread{} = thread) do
    Repo.one(
      from s in Session,
        where: s.thread_id == ^thread.id and is_nil(s.ended_at),
        order_by: [desc: s.id],
        limit: 1
    )
  end
end
