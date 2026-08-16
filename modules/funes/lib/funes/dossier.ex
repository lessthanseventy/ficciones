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

  alias Funes.Bus
  alias Funes.Event
  alias Funes.Fact
  alias Funes.Issue
  alias Funes.Message
  alias Funes.Question
  alias Funes.Repo
  alias Funes.Thread
  alias Funes.Todo

  # orient shows at most five open issues per thread; the rest is a number, never a
  # complete-and-useless list (§5 rank-and-cut, §1).
  @issue_cap 5

  # Open todos are capped the same way — a plan longer than five steps shows the next
  # five and counts the rest; a complete list is not a useful one (§5/§6).
  @todo_cap 5

  # Open questions (UNKNOWNS) cap identically — the brief shows five gaps and counts more.
  @question_cap 5

  @doc "Bank a durable fact. `{:ok, fact}` or `{:error, changeset}`."
  def bank_fact(attrs) do
    attrs |> Fact.bank_changeset() |> Repo.insert() |> Bus.announce(:fact_banked)
  end

  @doc """
  Bank a STATED fact from the operator's own message — §4's capture path made
  mechanical (pi doc §2a). `stated` outranks everything by construction, so it is
  reachable only THROUGH a message row: the fact quotes the message body VERBATIM
  and is scoped to the message's thread. The message must be authored by the
  operator (config `:operator`, case-insensitive) — an agent's paraphrase, or an
  agent quoted by another agent, laundered into the owner's instruction is the one
  abuse the provenance ordering makes possible, refused here rather than by rule.
  `attrs` carries the judgement half (`kind`, optionally `check_cmd`/`incident`).
  Returns `{:ok, fact}`, `{:error, :not_the_operator}`, or `{:error, changeset}`.
  """
  def bank_stated_fact(%Message{} = message, attrs) do
    operator = Application.get_env(:funes, :operator, "andrew")

    if String.downcase(message.author) == String.downcase(operator) do
      attrs
      |> Map.merge(%{
        text: message.body,
        provenance: "stated",
        thread_id: message.thread_id
      })
      |> bank_fact()
    else
      {:error, :not_the_operator}
    end
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
        where: f.provenance == "stated" and f.kind == "constraint" and f.id not in subquery(superseded),
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

  @doc "Add a plan step (todo) to a thread. `{:ok, todo}` or `{:error, changeset}`."
  def add_todo(attrs) do
    attrs |> Todo.add_changeset() |> Repo.insert() |> Bus.announce(:todo_added)
  end

  @doc """
  Mark a todo done — stamps `done_at`. Emits NO event: DONE is a merged view (todos by
  their `done_at`, plus `work_landed`), never a copy. `record_done` is the evidence-
  bearing verb for judgement-worthy outcomes.
  """
  def complete_todo(%Todo{} = todo) do
    todo |> Todo.done_changeset() |> Repo.update() |> Bus.announce(:todo_completed)
  end

  @doc "A todo by id, or nil — the load path for `complete_todo`, scope-checked by its tool."
  def todo(id), do: Repo.get(Todo, id)

  @doc """
  A thread's OPEN todos, ranked and cut (§5): `%{shown, more}`, `shown` at most five in
  INSERTION order (`id` asc) — so the head is NEXT, the derived first-open-todo. Completed
  todos and other threads' todos are excluded.
  """
  def open_todos_for_thread(%Thread{} = thread) do
    open = from t in Todo, where: t.thread_id == ^thread.id and is_nil(t.done_at)

    shown = Repo.all(from t in open, order_by: [asc: t.id], limit: @todo_cap)
    total = Repo.aggregate(open, :count, :id)

    %{shown: shown, more: total - length(shown)}
  end

  @doc """
  A thread's COMPLETED todos, most-recently-done first — the todo half of the DONE merged
  view. Ordered by `done_at` (then `id` for same-second ties), never copied into an event.
  """
  def done_todos_for_thread(%Thread{} = thread) do
    Repo.all(
      from t in Todo,
        where: t.thread_id == ^thread.id and not is_nil(t.done_at),
        order_by: [desc: t.done_at, desc: t.id]
    )
  end

  @doc "Raise a task question — a knowledge gap. `{:ok, question}` or `{:error, changeset}`."
  def raise_question(attrs) do
    attrs |> Question.raise_changeset() |> Repo.insert() |> Bus.announce(:question_raised)
  end

  @doc """
  Resolve a question — state resolved, `resolved_at` stamped, the optional `resolution`
  (the answer) recorded. A durable answer is banked as a `fact` separately; this only
  closes the gap. `{:ok, question}` or `{:error, changeset}`.
  """
  def resolve_question(%Question{} = question, resolution \\ nil) do
    question |> Question.resolve_changeset(resolution) |> Repo.update() |> Bus.announce(:question_resolved)
  end

  @doc "A question by id, or nil — the load path for `resolve_question`, scope-checked by its tool."
  def question(id), do: Repo.get(Question, id)

  @doc """
  A thread's OPEN questions, ranked and cut (§5): `%{shown, more}`, `shown` at most five
  (newest first) — the UNKNOWNS the brief surfaces beside FACTS. Resolved and other
  threads' questions are excluded.
  """
  def open_questions_for_thread(%Thread{} = thread) do
    open = from q in Question, where: q.thread_id == ^thread.id and q.state == "open"

    shown = Repo.all(from q in open, order_by: [desc: q.id], limit: @question_cap)
    total = Repo.aggregate(open, :count, :id)

    %{shown: shown, more: total - length(shown)}
  end
end
