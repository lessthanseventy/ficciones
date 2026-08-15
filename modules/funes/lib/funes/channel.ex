defmodule Funes.Channel do
  @moduledoc """
  The coordination spine (spec §5b, aleph §2/§9.2): threads and the messages on
  them. The channel is also §4's capture path — a message a participant posts is
  already a durable row, so intent becomes permanent as a side effect of talking.

  This context owns the durable **bus** (§10): rows in SQLite that exist and are
  readable with the BEAM node dead. The reactive **switchboard** — PubSub fan-out
  and waking an external session's pane — is a later layer over these rows, never
  what makes them exist.
  """
  import Ecto.Query
  alias Funes.{Message, Repo, Thread}

  @doc "Open a thread on the board. Returns `{:ok, thread}` or `{:error, changeset}`."
  def open_thread(attrs) do
    attrs |> Thread.open_changeset() |> Repo.insert()
  end

  @doc """
  Post a message to a thread — the capture path. Returns `{:ok, message}` or
  `{:error, changeset}` on a missing thread/author/body. A thread that does not
  exist is refused by SQLite's own foreign key (it raises), never by a mirrored
  check here (§10).
  """
  def post(attrs) do
    with {:ok, message} <- attrs |> Message.post_changeset() |> Repo.insert() do
      # Announce the durable row to the switchboard (liveness only, §10) — a
      # broadcast with no subscriber is a harmless no-op.
      Funes.Bus.broadcast_message(message)
      {:ok, message}
    end
  end

  @doc """
  Record that a message was delivered — the only path that may set `delivered_at`.
  This is the DB primitive the switchboard (a later increment) calls when it wakes
  a recipient; it means delivered, never read (§5b.3).
  """
  def mark_delivered(%Message{} = message) do
    message |> Message.delivered_changeset() |> Repo.update()
  end

  @doc "Close a thread. Its messages are untouched — history outlives the close."
  def close_thread(%Thread{} = thread) do
    thread |> Thread.state_changeset("closed") |> Repo.update()
  end

  @doc "Open threads only, newest first — closed threads are omitted."
  def open_threads do
    Repo.all(from t in Thread, where: t.state == "open", order_by: [desc: t.id])
  end

  @doc """
  A thread's messages in the order they were posted. Ordered by id, which is the
  true insertion order under §4's single writer — never by `created_at`, whose
  second resolution can tie.
  """
  def thread_messages(%Thread{} = thread) do
    Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: [asc: m.id])
  end
end
