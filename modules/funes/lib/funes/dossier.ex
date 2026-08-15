defmodule Funes.Dossier do
  @moduledoc """
  The dossier (aleph §9.4, spec §4/§5): `fact`, `event`, and `issue` scoped to a
  thread — the thread's accumulated state, and the source of LEARNINGS, SHIPPED and
  BLOCKERS. These are the judgement and the record a system cannot re-derive from a
  transcript; the channel (`Funes.Channel`) and the staff (`Funes.Staff`) own the
  rest of the spine.

  The per-thread reads here are raw material — `facts_for_thread`, `events_for_thread`
  and `shipped_for_thread` return every row, uncapped. Rank-and-cut (§5/§6) lives on
  the surface that renders LEARNINGS/SHIPPED, not built yet; only `open_issues_for_thread`
  caps today, because §5 makes its capped read the acceptance test that must exist now.
  """
  import Ecto.Query
  alias Funes.{Bus, Event, Fact, Issue, Repo, Thread}

  # orient shows at most five open issues per thread; the rest is a number, never a
  # complete-and-useless list (§5 rank-and-cut, §1).
  @issue_cap 5

  @doc "Bank a durable fact. `{:ok, fact}` or `{:error, changeset}`."
  def bank_fact(attrs) do
    attrs |> Fact.bank_changeset() |> Repo.insert() |> Bus.announce(:fact_banked)
  end

  @doc """
  The always-loaded constraint set (§4): `provenance='stated' AND kind='constraint'`,
  the ~32 rows every session reads at start. A superseded constraint is excluded —
  superseding is explicit (a later fact's `supersedes` points at it), never inferred
  from recency. Newest first.

  Only a PEER retires a peer: the superseding fact must itself be a stated
  constraint. His constraints outrank our conclusions by construction (§4), so a
  `derived` fact — a paraphrase of his instruction — must never silently retire one.
  """
  def always_loaded_constraints do
    superseded =
      from f in Fact,
        where: not is_nil(f.supersedes) and f.provenance == "stated" and f.kind == "constraint",
        select: f.supersedes

    Repo.all(
      from f in Fact,
        where:
          f.provenance == "stated" and f.kind == "constraint" and f.id not in subquery(superseded),
        order_by: [desc: f.id]
    )
  end

  @doc "A thread's facts, scoped to it, newest first — the raw material for LEARNINGS."
  def facts_for_thread(%Thread{} = thread) do
    Repo.all(from f in Fact, where: f.thread_id == ^thread.id, order_by: [desc: f.id])
  end

  @doc "Record an append-only event. `{:ok, event}` or `{:error, changeset}`."
  def record_event(attrs) do
    attrs |> Event.record_changeset() |> Repo.insert() |> Bus.announce(:event_recorded)
  end

  @doc "A thread's events, scoped to it, newest first."
  def events_for_thread(%Thread{} = thread) do
    Repo.all(from e in Event, where: e.thread_id == ^thread.id, order_by: [desc: e.id])
  end

  @doc """
  A thread's SHIPPED (§9.4): only `work_landed` events — the outcome kind, not the
  mechanism kinds around it. Newest first.
  """
  def shipped_for_thread(%Thread{} = thread) do
    Repo.all(
      from e in Event,
        where: e.thread_id == ^thread.id and e.kind == "work_landed",
        order_by: [desc: e.id]
    )
  end

  @doc "Raise a durable issue. `{:ok, issue}` or `{:error, changeset}`."
  def raise_issue(attrs) do
    attrs |> Issue.raise_changeset() |> Repo.insert() |> Bus.announce(:issue_raised)
  end

  @doc "Close an issue — a finding that has been settled."
  def resolve_issue(%Issue{} = issue) do
    issue |> Issue.state_changeset("closed") |> Repo.update() |> Bus.announce(:issue_resolved)
  end

  @doc """
  A thread's open issues, ranked and cut (§5): `%{shown: [issue], more: n}` where
  `shown` is at most five (newest first) and `more` counts the open issues beyond
  them. This is the BLOCKERS read `orient` calls at session start — the acceptance
  test §5 makes load-bearing: an issue table that no session reads must not exist.
  Closed issues and other threads' issues are excluded.
  """
  def open_issues_for_thread(%Thread{} = thread) do
    open = from i in Issue, where: i.thread_id == ^thread.id and i.state == "open"

    shown = Repo.all(from i in open, order_by: [desc: i.id], limit: @issue_cap)
    total = Repo.aggregate(open, :count, :id)

    %{shown: shown, more: total - length(shown)}
  end
end
