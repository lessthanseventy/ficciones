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
  2. **Warmth-gating (built).** A session idle longer than the prompt cache stays
     warm (~1h, `:warmth_window_seconds`) is **cold** — a poke would pay a full
     transcript re-ingestion instead of a cheap resume, the "resumed an old thread
     and burned my whole allotment" footgun. `recipients/1` excludes cold sessions
     (treated like ended ones), and the switchboard bumps `last_active_at` as a
     session acts — on being woken and on authoring (§3b, the warmth window).
     The OTHER half of "clocked out" — an engine out of credits or past its
     rate-limit window — is a pluggable presence signal not yet wired; combine it
     into `recipients/1` before an auto-poking Herdr/tmux backend replaces the
     default `Inert` arbiter.
  """
  import Ecto.Query
  require Logger
  alias Funes.{Agent, Arbiter, Mentions, Message, Presence, Repo, Session, Staff, Thread}

  @doc """
  Deliver one message (the live path): wake its addressed recipients (`recipients/1`),
  then stamp it delivered. A message no one live is addressed to stays undelivered
  (`:pending`) — it is not a delivery until someone is woken (§5b.3), and `drain/0`
  picks it up when a recipient appears. Returns `{:delivered, message}`,
  `{:pending, message}`, or `{:already_delivered, message}` when a concurrent drain
  won the claim first.
  """
  def deliver(%Message{} = message) do
    # Authoring is activity: keep the author's session warm even when nobody is woken
    # (a lead's report up to the human keeps the lead warm).
    touch_author(message)

    case recipients(message) do
      [] ->
        {:pending, message}

      sessions ->
        # Claim delivery ATOMICALLY, then wake — so the drain and the live handler
        # racing over the same message at startup can never both poke a paid pane.
        # Whoever flips delivered_at from NULL is the only one who wakes.
        if claim([message.id]) > 0 do
          waken(sessions, prompt(message))
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

    # Claim each message before collecting its recipients, so a wake is scoped to
    # what THIS drain actually claimed — a message a concurrent deliver already took
    # contributes nothing here.
    reached = Enum.flat_map(undelivered, &claim_reached/1)

    # Coalesce per pane, keeping the COUNT §3b wants ("you have 50 unread") — one
    # nudge per recipient, never one per message.
    reached
    |> Enum.group_by(& &1.pane_ref)
    |> Enum.each(fn {ref, sessions} ->
      poke(ref, "you have #{length(sessions)} unread message(s) on your threads")
    end)

    Staff.touch_sessions(reached |> Enum.map(& &1.id) |> Enum.uniq(), now())
  end

  # For drain: bump the author's warmth, then return the recipient sessions this call
  # actually claimed — empty if the message is unaddressed or a concurrent deliver
  # already won its claim.
  defp claim_reached(message) do
    touch_author(message)

    case recipients(message) do
      [] -> []
      sessions -> if claim([message.id]) > 0, do: sessions, else: []
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

  # Who a message wakes (the addressed-delivery model, aleph §2):
  #   * a REPLY  -> the author of the message it replies to
  #   * @mentions -> the named coworkers
  #   * neither (a plain top-level post) -> the thread's LEAD (its assigned agent)
  # minus the message's own author — you are never woken by your own words. The
  # lead stays informed without being cc'd because coworkers report back to the
  # thread (their top-level posts wake the lead).
  defp recipients(%Message{} = message) do
    # Match author↔agent case-INSENSITIVELY throughout (as @mentions already do), so
    # a mis-cased author handle can't silently drop a reply or strand an agent cold.
    author = String.downcase(message.author)
    targets = target_names(message) |> Enum.reject(&(String.downcase(&1) == author))

    case targets do
      [] ->
        []

      names ->
        # Only WARM sessions: live, addressed, and active within the cache window.
        # A cold session is treated like an ended one — never poked (§3b).
        wanted = Enum.map(names, &String.downcase/1)
        cutoff = Presence.warmth_cutoff()

        Repo.all(
          from s in Session,
            join: a in Agent,
            on: a.id == s.agent_id,
            where:
              s.thread_id == ^message.thread_id and is_nil(s.ended_at) and
                fragment("lower(?)", a.name) in ^wanted and s.last_active_at > ^cutoff
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

  # Poke each distinct pane once, and bump the woken sessions warm — being woken is
  # a turn, so it refreshes their warmth.
  defp waken(sessions, prompt) do
    sessions
    |> Enum.uniq_by(& &1.pane_ref)
    |> Enum.each(&poke(&1.pane_ref, prompt))

    Staff.touch_sessions(Enum.map(sessions, & &1.id), now())
  end

  # Actuate one wake, and SURFACE a backend failure rather than silently dropping
  # it. The Inert/Test backends never fail; a real Herdr/tmux one can, and a lost
  # nudge should at least be visible. (At-most-once retry semantics for a fallible
  # arbiter are settled when a real backend ships — see the moduledoc.)
  defp poke(pane_ref, prompt) do
    case Arbiter.wake(pane_ref, prompt) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("arbiter failed to wake #{inspect(pane_ref)}: #{inspect(reason)}")
    end
  end

  # Bump the author's live sessions on the thread to when they posted — authoring
  # is a turn. Forward-only via `Staff.touch_sessions/2` (warmth's one write path,
  # shared with the MCP channel), so a backlog drain never moves warmth backward.
  defp touch_author(%Message{thread_id: thread_id, author: author, created_at: at}) do
    down = String.downcase(author)

    ids =
      Repo.all(
        from s in Session,
          join: a in Agent,
          on: a.id == s.agent_id,
          where:
            s.thread_id == ^thread_id and is_nil(s.ended_at) and
              fragment("lower(?)", a.name) == ^down,
          select: s.id
      )

    Staff.touch_sessions(ids, at)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp prompt(%Message{author: author, body: body, thread_id: thread_id}) do
    "New message on thread #{thread_id} from #{author}: #{body}"
  end
end
