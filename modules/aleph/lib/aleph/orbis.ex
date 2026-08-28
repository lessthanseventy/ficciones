defmodule Aleph.Orbis do
  @moduledoc """
  ORBIS — the god-view survey DATA behind tertius, Orbis' **resident surveyor** (Orbis Tertius
  design, slice 2). tertius no longer sits as Tlön's center coworker in the operator's eye; its
  home view is this survey — the god-view over worlds. Every machine thread (root + leaves) is
  reduced to lead + status + conflict count, plus the open/stalled/done tallies. The single source
  of the rollup's semantics, shared by BOTH surfaces — the Tlön sidebar panel (`Aleph.Panel.Orbis`,
  via `Aleph.Cockpit`) and the `chat` tab's header strip (`Aleph.MachineChat.Loop`) — so a status
  rule never drifts between them.

  Pure data, no styling: `rollup/0` returns `%{summary: %{open, stalled, done, conflicts},
  rows: [%{id, title, lead, status, conflicts}], worlds: [%{id, name, summary, leaves}]}` (status
  `:open | :stalled | :done`), or `nil` when funes is down / there are no machine threads. `summary`
  and `rows` are the per-thread lens the LEAVES sidebar + chat-tab strip read; `worlds` is the
  survey's per-world rollup — grouped under the live funes worlds (`Aleph.Worlds`, Slice 1), each
  row carrying its world `id` (D0.3) — the face Orbis' Chorus renders as one row per world, and the
  survey's `Enter`/click resolve back to. Status derives from `Funes.Board.in_scope/1` (the
  same per-thread brief Triage reads) so it reflects real blockers/failed checks, never a
  self-report. The gather is guarded: a funes hiccup degrades to `nil`, never a crash.
  """

  alias Funes.Channel

  @spec rollup() :: %{summary: map(), rows: [map()], worlds: [map()]} | nil
  def rollup do
    rows =
      Channel.machine_threads()
      # Worklines share the chat read-model but are WORK ITEMS, not coworker leaves — the
      # survey's lead/status semantics were never theirs (they carry a stage instead).
      |> Enum.reject(&Map.get(&1.thread, :stage))
      |> Enum.map(&row(&1.thread))
      |> Enum.sort_by(&status_rank(&1.status))

    if rows == [], do: nil, else: %{summary: summarize(rows), rows: rows, worlds: worlds(rows)}
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Group the rollup rows under the live funes worlds (`Aleph.Worlds.all/0`, Slice 1 Task B3). With
  the single seeded Tlön world this is one row — identical to Slice 0. Reads the cached world list;
  `worlds/2` is the pure grouping over explicit `%{id, name}` refs (tested without the live cache).
  """
  @spec worlds([map()]) :: [%{id: term(), name: String.t(), summary: map(), leaves: [map()]}]
  def worlds(rows), do: worlds(rows, world_refs())

  @doc """
  Group `rows` under explicit `%{id, name}` world refs — every row carries its funes **id** (D0.3:
  the survey can't resolve a click/Enter to a world without one). Per-world leaf attribution is
  still coarse (Phase B): the first world carries all machine leaves; any further worlds get an
  empty, zeroed row — a real per-leaf world membership isn't modeled yet, so this is the Slice-1
  floor, not the final grouping. No world refs (funes genuinely down — the app self-seeds at
  boot) yields no rows; the survey renders empty rather than fabricating a world (reshape slice A).
  """
  @spec worlds([map()], [%{id: term(), name: String.t()}]) :: [
          %{id: term(), name: String.t(), summary: map(), leaves: [map()]}
        ]
  def worlds(_rows, []), do: []

  def worlds(rows, [first | rest]) do
    [
      %{id: first.id, name: first.name, summary: summarize(rows), leaves: rows}
      | Enum.map(rest, &%{id: &1.id, name: &1.name, summary: summarize([]), leaves: []})
    ]
  end

  # The funes world refs, guarded: a cache hiccup degrades to [] (→ empty survey).
  defp world_refs do
    Enum.map(Aleph.Worlds.all(), &%{id: &1.id, name: &1.name})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

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
