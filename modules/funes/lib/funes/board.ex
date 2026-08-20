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
  alias Funes.Recall
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
    todos = Dossier.open_todos_for_thread(thread)

    %{
      thread: thread,
      north_star: thread.title,
      lead: lead_name(thread),
      todos: todos,
      # NEXT is derived, never stored (§5/§6): the head of the open todos, or nil.
      next: List.first(todos.shown),
      done: done_view(thread),
      learnings: learnings(thread),
      # UNKNOWNS beside FACTS — knowing what you don't know is first-class (§4a).
      unknowns: Dossier.open_questions_for_thread(thread),
      blockers: Dossier.open_issues_for_thread(thread),
      # CHECKS — the recent MEASURED verifications (last check red or green), not a self-report.
      checks: Dossier.recent_checks_for_thread(thread),
      chatter: Channel.recent_messages(thread, @cap)
    }
  end

  @doc """
  The machine META-view: every OPEN machine-scope thread (root + leaves) as a COMPACT brief — the
  cross-leaf read the Orbis Tertius meta agent synthesizes from (design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`). Each leaf is trimmed to the synthesis
  essentials — lead, NEXT step, open BLOCKERS, and the message tail — drawn from the SAME `in_scope/1`
  aggregate a single thread's dossier reads (one read model, not a second truth). Root-first (oldest
  id). Machine-scope only, by construction: `Channel.open_machine_threads/0` never returns project
  work, so this can't become a cross-scope peephole.
  """
  def machine_overview do
    Enum.map(Channel.open_machine_threads(), fn thread ->
      s = in_scope(thread)

      %{
        thread_id: thread.id,
        title: thread.title,
        lead: s.lead,
        next: s.next && s.next.text,
        blockers: Enum.map(s.blockers.shown, & &1.summary),
        recent: Enum.map(s.chatter, &%{author: &1.author, body: &1.body})
      }
    end)
  end

  # DONE is a MERGED view (pi doc §5): completed todos by their `done_at`, plus
  # `work_landed` events for outcomes never planned as a todo — merged by their OWN
  # timestamps, never copied into one another (the amended-§4 pattern). Each entry is
  # tagged with its `source` so a renderer can tell a finished step from a shipped
  # outcome; most-recent first, capped WITH a count like every other pane.
  defp done_view(%Thread{} = thread) do
    todos = Enum.map(Dossier.done_todos_for_thread(thread), &%{source: :todo, at: &1.done_at, row: &1})
    events = Enum.map(Dossier.shipped_for_thread(thread), &%{source: :event, at: &1.created_at, row: &1})

    (todos ++ events)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> rank_and_cut()
  end

  # LEARNINGS: the forgetting engine's token-budgeted working set when the recall read path is on
  # (design: `docs/plans/2026-08-19-funes-forgetting-design.md`), else the recency top-five. The
  # flag (`:recall`'s `:enabled`) is off until the cutover is flipped — same `%{shown, more}` shape
  # either way, so `MCP.Brief` renders both blind to which fed it.
  defp learnings(%Thread{} = thread) do
    if Recall.read_enabled?(),
      do: Recall.thread_learnings(thread),
      else: thread |> Dossier.facts_for_thread() |> rank_and_cut()
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
