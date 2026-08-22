defmodule Aleph.Panel.AuthorTest do
  # AUTHOR — the Orbis author face's editable world list (D2.2). Pins the panel → styled-rows path
  # headlessly: one row per world with its counts, the cursor row washed :selected, an empty-state
  # placeholder, and the footer hints line.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Author

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "renders the ORBIS · author header, one row per world, and the footer hints" do
    data = %{
      worlds: [
        %{
          id: 1,
          name: "Tlön",
          type: "code",
          paths: ["modules/*"],
          roster: [%{"archetype" => "surveyor"}],
          scope: "machine"
        }
      ],
      cursor: 0
    }

    text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "ORBIS · author"
    assert text =~ "Tlön"
    assert text =~ "code"
    assert text =~ "1 paths"
    assert text =~ "1 roster"
    assert text =~ "n new"
    assert text =~ "d delete"
    assert text =~ "a survey"
  end

  test "no worlds renders the header and a create-hint placeholder, no crash" do
    text = %{worlds: [], cursor: 0} |> Author.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "ORBIS · author"
    assert text =~ "no worlds yet"
  end

  test "the cursor row washes :selected; every other row doesn't" do
    data = %{
      worlds: [
        %{id: 1, name: "Tlön", type: "code", paths: [], roster: []},
        %{id: 2, name: "Freedonia", type: "blank", paths: [], roster: []}
      ],
      cursor: 1
    }

    rows = Author.render(data, @rect)

    freedonia = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Freedonia" end))
    assert Enum.any?(freedonia, fn {_t, s} -> s == :selected end)

    tlon = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Tlön" end))
    refute Enum.any?(tlon, fn {_t, s} -> s == :selected end)
  end

  test "a missing type/paths/roster degrades gracefully instead of crashing" do
    data = %{worlds: [%{id: 1, name: "Bare"}], cursor: 0}
    text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "Bare"
    assert text =~ "0 paths"
    assert text =~ "0 roster"
  end

  test "pick/3 is a no-op for now — no editor yet (Chunk 2)" do
    data = %{worlds: [%{id: 1, name: "Tlön"}], cursor: 0}
    assert Author.pick(data, @rect, 2) == nil
  end
end
