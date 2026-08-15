defmodule Funes.Board do
  @moduledoc """
  The board's read models (aleph §4): pure aggregates a TUI (later a LiveView)
  renders, composed from the contexts. §7 — the board holds no truth of its own, it
  reads the public context functions. `in_scope/1` is the focused thread's brief,
  and is deliberately the SAME one-call read that catches a re-entering session up
  from the dossier rather than the transcript (§3b): one artifact, two consumers.

  Ranked and cut (§6): each pane is capped, the rest a count where it matters
  (`blockers` already carries `more`).
  """
  import Ecto.Query
  alias Funes.{Agent, Channel, Dossier, Repo, Thread}

  @cap 5

  @doc """
  The IN SCOPE brief for a thread — read fresh from the DB (the argument is just an
  id handle): NORTH STAR (title), the assigned lead, SHIPPED, LEARNINGS, BLOCKERS
  (capped + count), and CHATTER (the message tail).
  """
  def in_scope(%Thread{} = thread) do
    thread = Repo.get!(Thread, thread.id)

    %{
      thread: thread,
      north_star: thread.title,
      lead: lead_name(thread),
      shipped: Dossier.shipped_for_thread(thread) |> Enum.take(@cap),
      learnings: Dossier.facts_for_thread(thread) |> Enum.take(@cap),
      blockers: Dossier.open_issues_for_thread(thread),
      chatter: Channel.recent_messages(thread, @cap)
    }
  end

  defp lead_name(%Thread{agent_id: nil}), do: nil

  defp lead_name(%Thread{agent_id: agent_id}) do
    Repo.one(from a in Agent, where: a.id == ^agent_id, select: a.name)
  end
end
