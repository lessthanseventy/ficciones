defmodule Funes.Workline.Ledger do
  @moduledoc """
  The value ledger (worklines slice 6): a READ-MODEL over rows the stage machine already
  writes — stage_advanced events + workline threads. The playbook's indicators come out of
  coordination as a side effect, never a second telemetry system. `mise run funes:ledger`.
  """

  import Ecto.Query

  alias Funes.Event
  alias Funes.Repo
  alias Funes.Thread

  @doc "Every workline with its transitions, plus the tallies."
  def report do
    threads = Repo.all(from t in Thread, where: not is_nil(t.stage), order_by: [asc: t.id])

    by_thread =
      from(e in Event, where: e.kind == "stage_advanced", order_by: [asc: e.id])
      |> Repo.all()
      |> Enum.group_by(& &1.thread_id)

    worklines =
      Enum.map(threads, fn t ->
        transitions =
          for e <- Map.get(by_thread, t.id, []),
              do: %{from: e.detail["from"], to: e.detail["to"], at: e.created_at}

        %{
          id: t.id,
          slug: t.slug,
          title: t.title,
          stage: t.stage,
          awaiting: t.awaiting,
          born: t.born,
          opened_at: t.created_at,
          transitions: transitions
        }
      end)

    %{
      worklines: worklines,
      summary: %{
        open: Enum.count(worklines, &(&1.stage != "merged")),
        merged: Enum.count(worklines, &(&1.stage == "merged")),
        gated: Enum.count(worklines, & &1.awaiting)
      }
    }
  end

  @doc "The human-readable ledger."
  def render(%{worklines: []}), do: ~s(no worklines yet — open one: mise run funes:cli -- workline "<title>" <slug>)

  def render(%{worklines: worklines, summary: s}) do
    lines =
      Enum.map(worklines, fn w ->
        gate = if w.awaiting, do: " ⏸awaiting #{w.awaiting}", else: ""
        born = if w.born == "machine", do: " (machine-born)", else: ""
        "##{w.id} #{w.slug} · #{w.stage}#{gate}#{born} · #{length(w.transitions)} advances · opened #{date(w.opened_at)}"
      end)

    Enum.join(lines, "\n") <> "\n#{s.open} open · #{s.merged} merged · #{s.gated} gated"
  end

  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")
  defp date(_at), do: "?"
end
