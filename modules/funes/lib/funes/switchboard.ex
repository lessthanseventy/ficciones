defmodule Funes.Switchboard do
  @moduledoc """
  The switchboard — **liveness over the durable bus** (§10, §5b.2, aleph §6). A
  message is already a row when it is posted (`Funes.Channel`); the switchboard's
  only job is to make delivery *live*: decide who to wake and poke their pane
  through the arbiter. It must never be what makes a message *exist* — kill the
  BEAM node and every message is still a row, and `drain/0` re-delivers on restart,
  so no wake is lost.

  `delivered_at` in the DB is the durable truth of what was delivered; PubSub (the
  `Server`) is only the low-latency nudge.

  ## Two guard-rails against burning a five-hour window

  Waking pokes a *real, paid* agent session, so the wake is deliberately restrained:

  1. **Coalescing.** A backlog wakes a recipient ONCE, never once per message — a
     resumed thread with fifty undelivered messages is one "you have 50 unread,"
     not fifty turns. `drain/0` groups by thread and wakes each recipient a single
     time. (This is also §5b's noise rule.)
  2. **Presence-gating is required before a real arbiter ships (§3b).** A session
     that is *clocked out* MUST NOT be woken — and "clocked out" includes **cold**:
     idle longer than the prompt cache stays warm (~1h), where a poke would pay a
     full transcript re-ingestion instead of a cheap resume (§3b, the warmth
     window). That is precisely the "resumed an old thread and burned my whole
     allotment" footgun. This layer isn't built yet, which is exactly why the
     default arbiter is `Inert` (pokes nothing): the mechanism is safe to run before
     its governor exists. Do not wire an auto-poking Herdr/tmux backend until
     `recipients/2` also filters clocked-out and cold sessions.
  """
  import Ecto.Query
  alias Funes.{Agent, Arbiter, Message, Repo, Session}

  @doc """
  Deliver one message (the live path): wake every *other* live session on its
  thread, then stamp it delivered. A message with no live recipient stays
  undelivered (`:pending`) — it is not a delivery until someone is woken (§5b.3),
  and `drain/0` picks it up when a recipient appears. Returns `{:delivered, message}`
  or `{:pending, message}`.
  """
  def deliver(%Message{} = message) do
    case recipients(message.thread_id, [message.author]) do
      [] ->
        {:pending, message}

      sessions ->
        # Claim delivery ATOMICALLY, then wake — so the drain and the live handler
        # racing over the same message at startup can never both poke a paid pane.
        # Whoever flips delivered_at from NULL is the only one who wakes.
        if claim([message.id]) > 0 do
          Enum.each(sessions, &Arbiter.wake(&1.workspace_ref, prompt(message)))
          {:delivered, message}
        else
          {:already_delivered, message}
        end
    end
  end

  @doc """
  Deliver everything still undelivered, oldest first — the durability path (§10),
  run on switchboard start so messages posted while it was down are still woken.
  COALESCED: each thread's backlog wakes its recipients ONE time (the burst guard),
  then the whole batch is marked delivered.
  """
  def drain do
    Repo.all(from m in Message, where: is_nil(m.delivered_at), order_by: [asc: m.id])
    |> Enum.group_by(& &1.thread_id)
    |> Enum.each(fn {thread_id, msgs} -> drain_thread(thread_id, msgs) end)
  end

  defp drain_thread(thread_id, msgs) do
    authors = msgs |> Enum.map(& &1.author) |> Enum.uniq()

    # Wake a live session unless EVERY message in the backlog is its own — so a
    # participant who also posted is still woken about others' messages, but nobody
    # is woken about only their own words.
    case recipients(thread_id, only_own(authors, msgs)) do
      [] ->
        :pending

      sessions ->
        # Same atomic claim as deliver/1: stamp the still-undelivered messages, and
        # wake ONCE only if this drain actually claimed at least one — so a message
        # the live handler already delivered is not poked again here.
        if claim(Enum.map(msgs, & &1.id)) > 0 do
          prompt = "#{length(msgs)} new message(s) on thread #{thread_id}"
          Enum.each(sessions, &Arbiter.wake(&1.workspace_ref, prompt))
        end
    end
  end

  # Atomically flip delivered_at to now for the still-undelivered messages among
  # `ids`, returning how many this call actually claimed. The `is_nil` guard in the
  # WHERE is the race gate: exactly one caller wins each message, so exactly one
  # wakes for it. `delivered_at` is the durable delivery truth (§10), so the claim
  # is both the record and the lock.
  defp claim(ids) do
    stamp = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(m in Message, where: m.id in ^ids and is_nil(m.delivered_at)),
        set: [delivered_at: stamp]
      )

    count
  end

  # Live sessions on a thread whose agent is not in `exclude` (the authors we must
  # not wake about their own words). The author↔agent link is by name — a message's
  # author is a handle, not an agent FK.
  defp recipients(thread_id, exclude) do
    Repo.all(
      from s in Session,
        join: a in Agent,
        on: a.id == s.agent_id,
        where: s.thread_id == ^thread_id and is_nil(s.ended_at) and a.name not in ^exclude
    )
  end

  # For a coalesced batch: exclude an agent only if EVERY message in the backlog is
  # their own (no one else spoke), so a participant is still woken about others'
  # messages even if they also posted some.
  defp only_own(authors, msgs) do
    Enum.filter(authors, fn author -> Enum.all?(msgs, &(&1.author == author)) end)
  end

  defp prompt(%Message{author: author, body: body, thread_id: thread_id}) do
    "New message on thread #{thread_id} from #{author}: #{body}"
  end
end
