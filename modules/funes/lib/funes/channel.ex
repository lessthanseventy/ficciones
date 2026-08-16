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

  alias Funes.Message
  alias Funes.Repo
  alias Funes.Thread

  @doc "Open a thread on the board. Returns `{:ok, thread}` or `{:error, changeset}`."
  def open_thread(attrs) do
    attrs |> Thread.open_changeset() |> Repo.insert() |> Funes.Bus.announce(:thread_opened)
  end

  @doc """
  Post a message to a thread — the capture path. Returns `{:ok, message}` or
  `{:error, changeset}` on a missing thread/author/body. A thread that does not
  exist is refused by SQLite's own foreign key (it raises), never by a mirrored
  check here (§10).
  """
  def post(attrs) do
    with {:ok, message} <- attrs |> Message.post_changeset() |> Repo.insert() do
      # Announce the durable row (liveness only, §10) — a broadcast with no
      # subscriber is a harmless no-op.
      Funes.Bus.broadcast({:message_posted, message})
      {:ok, message}
    end
  end

  @doc "Close a thread. Its messages are untouched — history outlives the close."
  def close_thread(%Thread{} = thread) do
    thread
    |> Thread.state_changeset("closed")
    |> Repo.update()
    |> Funes.Bus.announce(:thread_closed)
  end

  @doc "Open threads only, newest first — closed threads are omitted."
  def open_threads do
    Repo.all(from t in Thread, where: t.state == "open", order_by: [desc: t.id])
  end

  @doc """
  The message with this id, or nil. The `from_message` hook for stated facts
  (`Dossier.bank_stated_fact/2`): a caller quotes a message by reference, never
  by paraphrase.
  """
  def message(id), do: Repo.get(Message, id)

  @doc """
  A thread's messages in the order they were posted. Ordered by id, which is the
  true insertion order under §4's single writer — never by `created_at`, whose
  second resolution can tie.
  """
  def thread_messages(%Thread{} = thread) do
    Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: [asc: m.id])
  end

  @doc """
  A thread's most recent messages, capped, in chat order (oldest of the window
  first) — CHATTER for the board (§4), which shows the tail, not the whole history.
  """
  def recent_messages(%Thread{} = thread, limit \\ 10) do
    from(m in Message, where: m.thread_id == ^thread.id, order_by: [desc: m.id], limit: ^limit)
    |> Repo.all()
    |> Enum.reverse()
  end
end
