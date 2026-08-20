defmodule Aleph.Panel.LeavesTest do
  # LEAVES rollup (was ORBIS panel): the machine-scoped vantage — a compact lens over the leaf
  # threads (lead + status + conflicts), navigable in Tlön nav. On-screen paint is the eye test in a
  # real terminal; this pins the panel → styled-rows path headlessly.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Leaves

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "nil data renders the header and a placeholder, no crash" do
    text = nil |> Leaves.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "LEAVES"
    assert text =~ "no machine threads"
  end

  test "renders the rollup summary counts and one line per leaf (lead + status)" do
    data = %{
      summary: %{open: 1, stalled: 1, done: 2, conflicts: 3},
      rows: [
        %{id: 2, title: "joke thread", lead: "pi-machine", status: :stalled, conflicts: 3},
        %{id: 3, title: "reaper fix", lead: "claude-machine", status: :open, conflicts: 0},
        %{id: 1, title: "shipped the seed", lead: "tertius-machine", status: :done, conflicts: 0}
      ]
    }

    text = data |> Leaves.render(@rect) |> lines() |> Enum.join("\n")

    # Rollup line: the operator's open / stalled / done buckets, with conflicts called out.
    assert text =~ "1 open"
    assert text =~ "1 stalled"
    assert text =~ "2 done"
    assert text =~ "3 conflicts"

    # Every leaf shows its title and its lead.
    assert text =~ "joke thread"
    assert text =~ "pi-machine"
    assert text =~ "reaper fix"
    assert text =~ "claude-machine"
    assert text =~ "shipped the seed"
    assert text =~ "tertius-machine"

    # A stalled leaf surfaces its conflict count so the trouble is visible at a glance.
    stalled_line = text |> String.split("\n") |> Enum.find(&(&1 =~ "joke thread"))
    assert stalled_line =~ "3"
  end

  test "no conflicts → the rollup line omits the conflicts clause (a clean board reads clean)" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 2, title: "a", lead: "pi-machine", status: :open, conflicts: 0},
        %{id: 3, title: "b", lead: "claude-machine", status: :open, conflicts: 0}
      ]
    }

    text = data |> Leaves.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "0 stalled"
    refute text =~ "conflict"
  end

  test "pick maps a leaf row to focusing that thread; the header rows and empties are no-ops" do
    data = %{
      summary: %{open: 1, stalled: 0, done: 0, conflicts: 0},
      rows: [%{id: 7, title: "a", lead: "pi-machine", status: :open, conflicts: 0}]
    }

    # Header block (LEAVES / blank / summary / blank) then the first leaf row.
    assert Leaves.pick(data, @rect, 4) == {:focus_thread, 7}
    assert Leaves.pick(data, @rect, 0) == nil
    assert Leaves.pick(nil, @rect, 4) == nil
  end

  test "the selected leaf's title washes :selected; the rest stay :normal" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 2, title: "first", lead: "pi", status: :open, conflicts: 0},
        %{id: 3, title: "second", lead: "cc", status: :open, conflicts: 0}
      ],
      selected: 1
    }

    rows = Leaves.render(data, @rect)

    style_of = fn needle ->
      Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t == needle, do: s end) end)
    end

    assert style_of.("second") == :selected
    assert style_of.("first") == :normal
  end
end
