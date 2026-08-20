defmodule Funes.Recall do
  @moduledoc """
  The forgetting engine's recall layer (design:
  `docs/plans/2026-08-19-funes-forgetting-design.md`): assemble the WORKING SET — the
  token-budgeted slice of memory that reaches an agent's context. Candidates are ranked by
  `relevance × strength` (`Funes.Recall.Strength`); the operator's pinned constraints are a floor
  that is always kept; the ranked remainder fills the remaining token budget and everything else
  falls out of context — never off disk (an explicit deeper search still finds it). `assemble/2`
  is the pure core; DB-backed gatherers feed it real candidates.
  """
  import Ecto.Query

  alias Funes.Dossier
  alias Funes.Event
  alias Funes.Fact
  alias Funes.Recall.Embedding
  alias Funes.Recall.Strength
  alias Funes.Repo
  alias Funes.Thread

  @check_kinds ["check_passed", "check_failed"]
  @default_budget 4000

  @type candidate :: %{
          optional(any()) => any(),
          relevance: number(),
          strength: number(),
          tokens: pos_integer(),
          pinned?: boolean()
        }

  @doc """
  Assemble the working set from scored candidates. Pinned candidates are kept unconditionally and
  first; non-pinned candidates with positive strength are ranked by `relevance × strength` and
  added while they fit the remaining `:budget` (tokens). Everything else is dropped from context.
  """
  @spec assemble([candidate()], keyword()) :: [candidate()]
  def assemble(candidates, opts) do
    budget = Keyword.fetch!(opts, :budget)
    {pinned, rest} = Enum.split_with(candidates, & &1.pinned?)

    pinned = Enum.sort_by(pinned, &score/1, :desc)
    remaining = max(budget - Enum.sum(Enum.map(pinned, & &1.tokens)), 0)

    ranked =
      rest
      |> Enum.filter(&(&1.strength > 0))
      |> Enum.sort_by(&score/1, :desc)
      |> fill(remaining)

    pinned ++ ranked
  end

  # Rank = relevance × strength. A dead (non-positive strength) fact scores at or below zero and
  # is dropped upstream; among the living, more-relevant-and-stronger wins.
  defp score(%{relevance: r, strength: s}), do: r * s

  # Greedily keep candidates whose tokens fit the running budget — skipping an over-budget fact so
  # a smaller lower-ranked one can still land, rather than stopping at the first that doesn't fit.
  defp fill(candidates, budget) do
    {kept, _left} =
      Enum.reduce(candidates, {[], budget}, fn c, {kept, left} ->
        if c.tokens <= left, do: {[c | kept], left - c.tokens}, else: {kept, left}
      end)

    Enum.reverse(kept)
  end

  @doc """
  Assemble a thread's working set from the DB: the pinned operator constraints plus the thread's
  facts, each scored by strength (from its touch events) and — for now — uniform relevance, cut to
  the token budget. Query-relevance (FTS × cosine) blends into `:relevance` in a later pass.
  """
  @spec working_set_for_thread(Thread.t(), keyword()) :: [candidate()]
  def working_set_for_thread(%Thread{} = thread, opts \\ []) do
    now = opts[:now] || DateTime.utc_now()
    budget = opts[:budget] || recall_budget()
    query_vec = query_vector(opts)

    constraints = Dossier.always_loaded_constraints()
    pinned_ids = MapSet.new(constraints, & &1.id)
    facts = Enum.uniq_by(constraints ++ Dossier.facts_for_thread(thread), & &1.id)

    ids = Enum.map(facts, & &1.id)
    checks = checks_by_fact(ids)
    superseded = superseded_ids(ids)

    facts
    |> Enum.map(fn f ->
      touches =
        Strength.touches_for(
          %{created_at: f.created_at, checks: Map.get(checks, f.id, []), superseded?: MapSet.member?(superseded, f.id)},
          now
        )

      %{
        id: f.id,
        fact: f,
        relevance: relevance(f, query_vec),
        strength: Strength.of(touches, now),
        tokens: est_tokens(f.text),
        pinned?: MapSet.member?(pinned_ids, f.id)
      }
    end)
    |> assemble(budget: budget)
  end

  # The query's embedding: a precomputed `:query_embedding` (the test/cached path), else embed the
  # `:query` string via ollama, else nil (a session-start recall with no query → uniform relevance).
  defp query_vector(opts) do
    cond do
      vec = opts[:query_embedding] -> vec
      q = opts[:query] -> (case Embedding.embed(q, model: embedding_model()) do
                             {:ok, vec} -> vec
                             {:error, _} -> nil
                           end)
      true -> nil
    end
  end

  # Semantic relevance = cosine(query, fact-embedding), floored at 0 (anti-similar is irrelevant,
  # not negative). No query → uniform 1.0 (rank by pure strength); an un-embedded fact scores 0
  # under a query (keyword FTS will carry it in the follow-up blend).
  defp relevance(_fact, nil), do: 1.0
  defp relevance(%{embedding: nil}, _query_vec), do: 0.0
  defp relevance(%{embedding: emb}, query_vec), do: max(Embedding.cosine(query_vec, emb), 0.0)

  @doc "Store a fact's embedding vector + model (written after `bank_fact`, off the write path)."
  @spec store_embedding(Fact.t(), [float()], String.t()) :: {:ok, Fact.t()} | {:error, term()}
  def store_embedding(%Fact{} = fact, vector, model) do
    fact |> Fact.embedding_changeset(vector, model) |> Repo.update()
  end

  @doc """
  Best-effort: embed a fact's text with the configured model and store the vector. A down embedder
  is a no-op (`{:error, _}`, recall falls back to keyword) — it never blocks or fails the caller.
  """
  @spec embed_fact(Fact.t()) :: {:ok, Fact.t()} | {:error, term()}
  def embed_fact(%Fact{} = fact) do
    model = embedding_model()

    case Embedding.embed(fact.text, model: model) do
      {:ok, vector} -> store_embedding(fact, vector, model)
      {:error, reason} -> {:error, reason}
    end
  end

  defp embedding_model, do: get_in(Application.get_env(:funes, :embedding, []), [:model]) || "nomic-embed-text"

  defp recall_budget, do: get_in(Application.get_env(:funes, :recall, []), [:budget]) || @default_budget

  # ~4 chars per token — a rough estimate, enough to bound the working set by tokens (design: a
  # budget, not a row count). A precise tokenizer can replace this without changing the seam.
  defp est_tokens(text), do: max(div(String.length(text || ""), 4), 1)

  # Each fact's recheck events, grouped by fact id — the correlation is `"fact:<id>"`.
  defp checks_by_fact([]), do: %{}

  defp checks_by_fact(fact_ids) do
    correlations = Enum.map(fact_ids, &"fact:#{&1}")

    from(e in Event, where: e.correlation in ^correlations and e.kind in ^@check_kinds, select: {e.correlation, e.kind, e.created_at})
    |> Repo.all()
    |> Enum.group_by(fn {corr, _kind, _at} -> fact_id_of(corr) end, fn {_corr, kind, at} -> %{kind: kind, at: at} end)
  end

  defp fact_id_of("fact:" <> id), do: String.to_integer(id)

  # The set of fact ids that a later fact supersedes — a hard-negative touch.
  defp superseded_ids([]), do: MapSet.new()

  defp superseded_ids(fact_ids) do
    from(f in Fact, where: not is_nil(f.supersedes) and f.supersedes in ^fact_ids, select: f.supersedes)
    |> Repo.all()
    |> MapSet.new()
  end
end
