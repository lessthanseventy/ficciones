defmodule Funes.Board do
  @moduledoc """
  The board's read models (aleph §4): pure aggregates a TUI (later a LiveView)
  renders, composed from the contexts. §7 — the board holds no truth of its own, it
  reads the public context functions. `in_scope/1` is the focused thread's brief,
  and is deliberately the SAME one-call read that catches a re-entering session up
  from the dossier rather than the transcript (§3b): one artifact, two consumers.

  Ranked and cut (§6): each pane is capped WITH a count. For an agent briefed from
  this map (the MCP channel's `get_dossier`), a cut without a count reads as "this
  is everything" — the empty-world lie in miniature — so LEARNINGS, SHIPPED and
  BLOCKERS are each `%{shown, more}`.
  """
  import Ecto.Query

  alias Funes.Agent
  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.Repo
  alias Funes.Thread

  @cap 5

  @doc """
  The IN SCOPE brief for a thread — read fresh from the DB (the argument is just an
  id handle): NORTH STAR (title), the assigned lead, SHIPPED, LEARNINGS and
  BLOCKERS each `%{shown, more}`, and CHATTER (the message tail).
  """
  def in_scope(%Thread{} = thread) do
    thread = Repo.get!(Thread, thread.id)

    %{
      thread: thread,
      north_star: thread.title,
      lead: lead_name(thread),
      shipped: thread |> Dossier.shipped_for_thread() |> rank_and_cut(),
      learnings: thread |> Dossier.facts_for_thread() |> rank_and_cut(),
      blockers: Dossier.open_issues_for_thread(thread),
      chatter: Channel.recent_messages(thread, @cap)
    }
  end

  # Cap a ranked list and COUNT the cut — never a silent truncation (§5/§6).
  defp rank_and_cut(rows) do
    shown = Enum.take(rows, @cap)
    %{shown: shown, more: length(rows) - length(shown)}
  end

  defp lead_name(%Thread{agent_id: nil}), do: nil

  defp lead_name(%Thread{agent_id: agent_id}) do
    Repo.one(from a in Agent, where: a.id == ^agent_id, select: a.name)
  end
end
