defmodule Funes.WorklineLedgerTest do
  # Worklines slice 6: the value ledger — a READ-MODEL over rows the stage machine already
  # writes (stage_advanced events + thread state). No new telemetry system; the metrics are
  # a side effect of coordination.
  use ExUnit.Case, async: false

  alias Funes.Workline
  alias Funes.Workline.Ledger

  defmodule AllPresent do
    @moduledoc false
    @behaviour Funes.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "present"}
  end

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  test "the report carries every workline's stage, transitions, and the tallies" do
    {:ok, a} = Workline.open(%{title: "one", slug: "line-a"})
    {:ok, a} = Workline.advance(a, artifacts: AllPresent)
    {:awaiting, _a} = Workline.advance(a, artifacts: AllPresent)
    {:ok, _b} = Workline.open(%{title: "two", slug: "line-b"})

    report = Ledger.report()

    assert report.summary.open == 2
    assert report.summary.gated == 1
    assert report.summary.merged == 0

    line_a = Enum.find(report.worklines, &(&1.slug == "line-a"))
    assert line_a.stage == "spec"
    assert line_a.awaiting == "andrew"
    assert [%{from: "intent", to: "spec", at: %DateTime{}}] = line_a.transitions

    rendered = Ledger.render(report)
    assert rendered =~ "line-a"
    assert rendered =~ "spec"
    assert rendered =~ "gated"
  end

  test "an empty machine renders honestly" do
    report = Ledger.report()
    assert report.worklines == []
    assert Ledger.render(report) =~ "no worklines"
  end
end
