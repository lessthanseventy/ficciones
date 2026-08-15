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

  ## Addressed delivery — a message wakes who it is addressed to, not the room

  A plain top-level post wakes only the thread's **lead** (its assigned agent, the
  orchestrator); an **@mention** wakes that coworker; a **reply** wakes the author of
  the message it answers. Never the whole room — the lead stays informed because
  coworkers report back to the thread. See `recipients/1`.

  ## Two guard-rails against burning a five-hour window

  Waking pokes a *real, paid* agent session, so the wake is deliberately restrained:

  1. **Coalescing.** A backlog wakes each pane ONCE, never once per message — a
     resumed thread with fifty undelivered messages is one nudge, not fifty turns
     (`drain/0` dedups panes; also §5b's noise rule).
  2. **Presence-gating is required before a real arbiter ships (§3b).** A session
     that is *clocked out* MUST NOT be woken — and "clocked out" includes **cold**:
     idle longer than the prompt cache stays warm (~1h), where a poke would pay a
     full transcript re-ingestion instead of a cheap resume (§3b, the warmth
     window). That is precisely the "resumed an old thread and burned my whole
     allotment" footgun. This layer isn't built yet, which is exactly why the
     default arbiter is `Inert` (pokes nothing): the mechanism is safe to run before
     its governor exists. Do not wire an auto-poking Herdr/tmux backend until
     `recipients/1` also filters clocked-out and cold sessions.
  """
  import Ecto.Query
  alias Funes.{Agent, Arbiter, Mentions, Message, Repo, Session, Thread}

  @doc """
  Deliver one message (the live path): wake its addressed recipients (`recipients/1`),
  then stamp it delivered. A message no one live is addressed to stays undelivered
  (`:pending`) — it is not a delivery until someone is woken (§5b.3), and `drain/0`
  picks it up when a recipient appears. Returns `{:delivered, message}` or
  `{:pending, message}`.
  """
  def deliver(%Message{} = message) do
    case recipients(message) do
      [] ->
        {:pending, message}

      sessions ->
        # Claim delivery ATOMICALLY, then wake — so the drain and the live handler
        # racing over the same message at startup can never both poke a paid pane.
        # Whoever flips delivered_at from NULL is the only one who wakes.
        if claim([message.id]) > 0 do
          wake(Enum.map(sessions, & &1.workspace_ref), prompt(message))
          {:delivered, message}
        else
          {:already_delivered, message}
        end
    end
  end

  @doc """
  Deliver everything still undelivered, oldest first — the durability path (§10),
  run on switchboard start so messages posted while it was down are still woken.
  COALESCED per recipient: each distinct pane is woken ONCE for the whole backlog
  (the burst guard), and only the messages that actually reached someone are marked
  delivered.
  """
  def drain do
    undelivered =
      Repo.all(from m in Message, where: is_nil(m.delivered_at), order_by: [asc: m.id])

    # Claim each message before collecting its panes, so a wake is scoped to what
    # THIS drain actually claimed — a message a concurrent deliver already took
    # contributes no pane here. wake/2 then dedups, so each pane fires once.
    undelivered
    |> Enum.flat_map(fn message ->
      case recipients(message) do
        [] ->
          []

        sessions ->
          if claim([message.id]) > 0, do: Enum.map(sessions, & &1.workspace_ref), else: []
      end
    end)
    |> wake("you have unread messages")
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

  # Who a message wakes (the addressed-delivery model, aleph §2):
  #   * a REPLY  -> the author of the message it replies to
  #   * @mentions -> the named coworkers
  #   * neither (a plain top-level post) -> the thread's LEAD (its assigned agent)
  # minus the message's own author — you are never woken by your own words. The
  # lead stays informed without being cc'd because coworkers report back to the
  # thread (their top-level posts wake the lead).
  defp recipients(%Message{} = message) do
    targets = target_names(message) -- [message.author]

    case targets do
      [] ->
        []

      names ->
        Repo.all(
          from s in Session,
            join: a in Agent,
            on: a.id == s.agent_id,
            where: s.thread_id == ^message.thread_id and is_nil(s.ended_at) and a.name in ^names
        )
    end
  end

  defp target_names(%Message{} = message) do
    case reply_author(message) ++ mentioned_agents(message) do
      [] -> lead_name(message)
      addressed -> Enum.uniq(addressed)
    end
  end

  defp reply_author(%Message{reply_to: nil}), do: []

  defp reply_author(%Message{reply_to: parent_id}) do
    case Repo.get(Message, parent_id) do
      %Message{author: author} -> [author]
      nil -> []
    end
  end

  # The @-handles that name a real agent — an @here that matches no agent wakes no
  # one, and (because it resolves to nothing) does not suppress the lead default.
  # Matched case-INSENSITIVELY so a wrong-case @robert still reaches Robert rather
  # than silently falling back to the lead; the agent's real name is returned.
  defp mentioned_agents(%Message{body: body}) do
    case Mentions.names(body) do
      [] ->
        []

      handles ->
        wanted = Enum.map(handles, &String.downcase/1)
        Repo.all(from a in Agent, where: fragment("lower(?)", a.name) in ^wanted, select: a.name)
    end
  end

  defp lead_name(%Message{thread_id: thread_id}) do
    with %Thread{agent_id: agent_id} when not is_nil(agent_id) <- Repo.get(Thread, thread_id),
         %Agent{name: name} <- Repo.get(Agent, agent_id) do
      [name]
    else
      _ -> []
    end
  end

  defp wake(panes, prompt), do: panes |> Enum.uniq() |> Enum.each(&Arbiter.wake(&1, prompt))

  defp prompt(%Message{author: author, body: body, thread_id: thread_id}) do
    "New message on thread #{thread_id} from #{author}: #{body}"
  end
end
