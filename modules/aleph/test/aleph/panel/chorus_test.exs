defmodule Aleph.Panel.ChorusTest do
  # CHORUS — Orbis' center, re-pointed from a per-thread feed to the per-WORLD survey (Slice 0: one
  # hardcoded world, Tlön). On-screen paint is the eye test; this pins the panel → styled-rows path
  # headlessly (no termbox), asserting the header + world row + its rollup summary.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Chorus

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "renders the ORBIS · worlds header and one world row with its rollup summary" do
    data = %{
      worlds: [
        %{
          world: "Tlön",
          summary: %{open: 2, stalled: 1, done: 3, conflicts: 4},
          leaves: [%{id: 1}, %{id: 2}]
        }
      ]
    }

    text = data |> Chorus.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "ORBIS · worlds"
    assert text =~ "Tlön"

    # The world's summary line carries the leads/open/stalled/done/trouble rollup.
    assert text =~ "2 open"
    assert text =~ "1 stalled"
    assert text =~ "3 done"
    assert text =~ "4 conflicts"
  end

  test "no worlds (funes down / empty) renders the header and a placeholder, no crash" do
    text = %{worlds: []} |> Chorus.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "ORBIS · worlds"
    assert text =~ "no worlds"
  end

  test "clicking a world row zooms to its lens (the Tlön space); the header is inert" do
    data = %{
      worlds: [%{world: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}]
    }

    # Header (0) + blank (1), then the world's rows start at y = 2.
    assert Chorus.pick(data, @rect, 2) == {:switch_space, 0}
    assert Chorus.pick(data, @rect, 0) == nil
  end
end
