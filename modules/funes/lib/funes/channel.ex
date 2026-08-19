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

  alias Funes.Agent
  alias Funes.Event
  alias Funes.Fact
  alias Funes.Habit
  alias Funes.Issue
  alias Funes.Message
  alias Funes.Question
  alias Funes.Repo
  alias Funes.Session
  alias Funes.Staff
  alias Funes.Thread
  alias Funes.Todo

  # The closed thread-scope set (CHECK-guarded in the DB — see the thread_scope migration).
  # Every scope filter pins one of these, so a future third scope is a grep for the attribute,
  # not a hunt for string literals.
  @project_scope "project"
  @machine_scope "machine"

  @doc ~s(Open a thread on the board. Returns `{:ok, thread}` or `{:error, changeset}`.
  `scope` defaults to `"project"`; the Tlön machine-coworker path opens with `"machine"`.)
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

  @doc "Open PROJECT threads only, newest first — closed and machine-scope threads are omitted.
  The machine thread (the Tlön coworker) is filtered out of the project surfaces; reach it via
  `machine_thread/0` or by id. (aleph Tlön isolation, 2026-08-16.)"
  def open_threads do
    Repo.all(from t in Thread, where: t.state == "open" and t.scope == ^@project_scope, order_by: [desc: t.id])
  end

  @doc "The latest open MACHINE-scope thread, or nil — the find-or-create lookup for the Tlön
  machine coworker, so it reuses a persistent machine thread across aleph restarts instead of
  opening one per boot."
  def machine_thread do
    Repo.one(from t in Thread, where: t.state == "open" and t.scope == ^@machine_scope, order_by: [desc: t.id], limit: 1)
  end

  @doc """
  STAFFED machine-scope threads — B1.4's `ensure_thread_sessions` candidate list (aleph
  cockpit.ex): every machine-scope thread with a lead, `%{id, lead, title}` per thread (`lead` is
  the staffed agent's name; the join makes it never nil). No open/closed filter and no ordering
  guarantee — the cockpit does its own dedup against live tmux windows and its own retry backoff.
  """
  def staffed_machine_threads do
    Repo.all(
      from t in Thread,
        join: a in Agent,
        on: a.id == t.agent_id,
        where: t.scope == ^@machine_scope and not is_nil(t.agent_id),
        select: %{id: t.id, lead: a.name, title: t.title}
    )
  end

  @doc """
  Delete every MACHINE-scope thread and everything hanging off it — the clean-slate reset behind
  `mise run aleph:clear-machine-threads` (B1.4's design doc: old machine threads are disposable).

  Every table with a `thread_id` FK must be cleared before the threads themselves: SQLite's FKs
  are `NO ACTION`, so a single surviving child row rejects the whole thread delete (the bug this
  replaces cleared only `message` — a machine thread with a `session`/`fact`/`todo`/... blew up on
  the thread delete and rolled the transaction back). Two wrinkles in the child sweep:

    * `fact` references `session` (`fact.source_session_id`), so facts must be deleted BEFORE
      sessions, or the session delete trips that FK.
    * `habit` is machine-WIDE and only cites the proposing thread as nullable provenance
      (`source_thread_id`) — we null that pointer instead of deleting the habit, so a clean-slate
      never discards learned behavior.

  If a new table gains a `thread_id` FK, add it to the sweep below. All of it runs in one
  transaction. Returns `{:ok, %{threads: n, messages: m}}` so the caller can report what it
  cleared. NEVER touches project-scope threads.
  """
  def clear_machine_threads do
    Repo.transaction(fn ->
      ids = Repo.all(from t in Thread, where: t.scope == ^@machine_scope, select: t.id)

      Repo.update_all(from(h in Habit, where: h.source_thread_id in ^ids), set: [source_thread_id: nil])

      # Fact before Session (fact.source_session_id FK); the rest only reference thread_id.
      for schema <- [Fact, Session, Event, Issue, Question, Todo] do
        Repo.delete_all(from r in schema, where: r.thread_id in ^ids)
      end

      {messages, _} = Repo.delete_all(from m in Message, where: m.thread_id in ^ids)
      {threads, _} = Repo.delete_all(from t in Thread, where: t.id in ^ids)
      %{threads: threads, messages: messages}
    end)
  end

  @doc """
  ALL machine-scope threads as THREAD BLOCKS — the Tlön machine-chat surface (aleph's `chat` tab).
  Like `chorus/1` but scoped to `machine` and WITHOUT the open-only filter: a rotated (closed)
  machine thread must still surface as history, so the chat can fold it below the current one.
  Each block carries the thread's recent messages (chat order within), most-recent-activity FIRST.
  `[%{thread, messages}]`.
  """
  def machine_threads(per_thread \\ 20) do
    by_thread = 300 |> recent_across() |> Enum.group_by(& &1.thread_id)

    from(t in Thread, where: t.scope == ^@machine_scope)
    |> Repo.all()
    |> Enum.map(fn t ->
      messages = by_thread |> Map.get(t.id, []) |> Enum.take(-per_thread)
      %{thread: t, messages: messages}
    end)
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  @doc "A thread by id, or nil — the load path for the cross-thread `close_thread` verb."
  def thread(id), do: Repo.get(Thread, id)

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

  @doc """
  The most recent message on `thread_id` authored by the configured operator (config `:operator`,
  case-insensitive — see `Dossier.bank_stated_fact/2`), or nil. B1.4's opening-turn source: a
  freshly spawned per-thread window is woken with the operator's own words, verbatim, never an
  agent's paraphrase.
  """
  def latest_operator_message(thread_id) do
    operator = :funes |> Application.get_env(:operator, "andrew") |> String.downcase()

    Repo.one(
      from m in Message,
        where: m.thread_id == ^thread_id and fragment("lower(?)", m.author) == ^operator,
        order_by: [desc: m.id],
        limit: 1
    )
  end

  @doc """
  Recent messages ACROSS all threads — the Comms rollup feed (a "slack for agents" timeline, not
  one channel). Each row carries its `thread_id` + `thread_title` so the surface can group the
  feed by thread. Newest `limit` messages, returned oldest-first (chat order, newest at the
  bottom like a chat log).
  """
  def recent_across(limit \\ 50) do
    from(m in Message,
      join: t in Thread,
      on: t.id == m.thread_id,
      order_by: [desc: m.id],
      limit: ^limit,
      select: %{
        id: m.id,
        thread_id: m.thread_id,
        thread_title: t.title,
        author: m.author,
        body: m.body,
        reply_to: m.reply_to,
        created_at: m.created_at
      }
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  The Comms chorus as THREAD BLOCKS — one entry per OPEN **project** thread, each with its recent messages
  (chat order within), ordered by most-recent-activity FIRST. Every open project thread appears,
  including one with no messages yet (a fresh thread you just spawned onto) — so the feed and the
  ↑/↓ navigator share ONE order and every focusable thread is visible. The machine-scope thread
  (the Tlön coworker) is excluded — it's a meta thread, not project work; reach it via the Tlön
  space. `[%{thread, messages}]`.

  Ordered by message **id**, never `created_at` — its second resolution ties (§4), which would
  make the feed order flap. Threads with messages lead (newest message first); threads with none
  trail (newest thread first), so a just-made quiet thread is visible at the bottom, not lost.
  """
  def chorus(per_thread \\ 20) do
    by_thread = 300 |> recent_across() |> Enum.group_by(& &1.thread_id)

    from(t in Thread, where: t.state == "open" and t.scope == ^@project_scope)
    |> Repo.all()
    |> Enum.map(fn t ->
      messages = by_thread |> Map.get(t.id, []) |> Enum.take(-per_thread)
      %{thread: t, messages: messages}
    end)
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  # {tier, id}: threads WITH messages (tier 1) rank above empty ones (tier 0); within a tier the
  # higher id (newest message, else newest thread) leads. A total order, no created_at tie.
  defp sort_key(%{messages: [], thread: %Thread{id: id}}), do: {0, id}
  defp sort_key(%{messages: messages}), do: {1, List.last(messages).id}

  @doc """
  Staff `thread_id` with the agent named `handle` — the aleph machine-chat staffing call, a single
  clean boundary crossing over a resolve-then-assign. `{:ok, thread}` on success; `{:error,
  :no_agent}` when the handle has never registered (a coworker not yet staffed — a no-op, not a
  crash); `{:error, :no_thread}` when the thread id doesn't resolve.
  """
  def assign_lead(thread_id, handle) do
    with %Agent{} = agent <- Staff.agent_by_name(handle) || {:error, :no_agent},
         %Thread{} = thread <- thread(thread_id) || {:error, :no_thread} do
      Staff.assign(thread, agent)
    end
  end

  @doc "The name of the agent staffed on `thread_id` (its lead), or nil if unassigned/absent."
  def thread_lead(thread_id) do
    Repo.one(
      from t in Thread,
        join: a in Agent,
        on: a.id == t.agent_id,
        where: t.id == ^thread_id,
        select: a.name
    )
  end
end
