defmodule Aleph.Panel.HabitsTest do
  # The habits panel (pi-synthesis slice 4): a pure view over funes' pending + approved habits,
  # rendered on Tlön. On-screen paint (cells → termbox) is the eye test in a real terminal; this
  # pins the panel → styled-rows path headlessly, the same boundary Aleph.BoardTest draws.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Habits

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "nil data renders the header and a placeholder, no crash" do
    text = nil |> Habits.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "HABITS"
    assert text =~ "no habits yet"
  end

  test "renders PENDING (with the proposing agent) and APPROVED, each with its count" do
    data = %{
      pending: [%{text: "run mise run check before a commit", proposed_by: "glm-5.2"}],
      approved: [%{text: "prefer the Claude bucket"}]
    }

    text = data |> Habits.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "PENDING (1)"
    assert text =~ "run mise run check before a commit"
    assert text =~ "glm-5.2"
    assert text =~ "APPROVED (1)"
    assert text =~ "prefer the Claude bucket"
  end

  test "an empty section renders a dim placeholder with its zero count — a cut without a count lies" do
    text = %{pending: [], approved: []} |> Habits.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "PENDING (0)"
    assert text =~ "APPROVED (0)"
    assert text =~ "—"
  end
end
