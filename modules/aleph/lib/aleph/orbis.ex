defmodule Aleph.Orbis do
  @moduledoc """
  ORBIS — the machine-scoped **rollup** DATA (Orbis Tertius design, slice 2): every machine thread
  (root + leaves) reduced to lead + status + conflict count, plus the open/stalled/done tallies.
  The single source of the rollup's semantics, shared by BOTH surfaces — the Tlön sidebar panel
  (`Aleph.Panel.Orbis`, via `Aleph.Cockpit`) and the `chat` tab's header strip
  (`Aleph.MachineChat.Loop`) — so a status rule never drifts between them.

  Pure data, no styling: `rollup/0` returns `%{summary: %{open, stalled, done, conflicts},
  rows: [%{id, title, lead, status, conflicts}], worlds: [%{world, summary, leaves}]}` (status
  `:open | :stalled | :done`), or `nil` when funes is down / there are no machine threads. `summary`
  and `rows` are the per-thread lens the LEAVES sidebar + chat-tab strip read; `worlds` groups those
  same rows under a single hardcoded world (Tlön) — the Slice 0 survey face Orbis' Chorus renders,
  one row per world. Status derives from `Funes.Board.in_scope/1` (the same per-thread brief Triage
  reads) so it reflects real blockers/failed checks, never a self-report. The gather is guarded: a
  funes hiccup degrades to `nil`, never a crash.
  """

  alias Funes.Channel

  # Slice 0: one hardcoded world. Slice 1 moves this to funes-owned composition data.
  @world "Tlön"

  @spec rollup() :: %{summary: map(), rows: [map()], worlds: [map()]} | nil
  def rollup do
    rows =
      Channel.machine_threads()
      |> Enum.map(&row(&1.thread))
      |> Enum.sort_by(&status_rank(&1.status))

    if rows == [], do: nil, else: %{summary: summarize(rows), rows: rows, worlds: worlds(rows)}
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Group the rollup rows under the single hardcoded world (Slice 0: one world, Tlön). Pure — the
  survey face pins its world shape against this, since `rollup/0` itself needs live funes.
  """
  @spec worlds([map()]) :: [%{world: String.t(), summary: map(), leaves: [map()]}]
  def worlds(rows), do: [%{world: @world, summary: summarize(rows), leaves: rows}]

  defp row(thread) do
    scope = Funes.Board.in_scope(thread)
    conflicts = length(scope.blockers.shown) + scope.blockers.more + failed_checks(scope)
    %{id: thread.id, title: thread.title, lead: scope.lead, status: status(thread.state, conflicts), conflicts: conflicts}
  end

  @doc """
  A thread's status from its state and conflict count: a CLOSED thread is `:done`; an open one with
  a blocker or failed check is `:stalled`; else it is `:open` (in flight).
  """
  @spec status(String.t(), non_neg_integer()) :: :open | :stalled | :done
  def status("closed", _conflicts), do: :done
  def status(_state, conflicts) when conflicts > 0, do: :stalled
  def status(_state, _conflicts), do: :open

  @doc "The open/stalled/done tallies + total conflicts across a list of rollup rows."
  @spec summarize([map()]) :: %{
          open: non_neg_integer(),
          stalled: non_neg_integer(),
          done: non_neg_integer(),
          conflicts: non_neg_integer()
        }
  def summarize(rows) do
    by = Enum.frequencies_by(rows, & &1.status)

    %{
      open: Map.get(by, :open, 0),
      stalled: Map.get(by, :stalled, 0),
      done: Map.get(by, :done, 0),
      conflicts: Enum.reduce(rows, 0, &(&1.conflicts + &2))
    }
  end

  defp failed_checks(scope), do: Enum.count(scope.checks.shown, &(&1.kind == "check_failed"))

  # Stalled sorts first so trouble rides the top of the lens; open before the settled done rows.
  defp status_rank(:stalled), do: 0
  defp status_rank(:open), do: 1
  defp status_rank(:done), do: 2
end
