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
end
