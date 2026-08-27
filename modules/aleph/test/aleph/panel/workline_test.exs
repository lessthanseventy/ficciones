defmodule Aleph.Panel.WorklineTest do
  # WORKLINES pane: the stage machine made legible — one row per open workline (stage, gate,
  # blocking verify check) — pure over Funes.Workline.Ledger.statuses/0. On-screen paint is the
  # eye test in a real terminal; this pins the panel → styled-rows path headlessly.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Workline

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  defp w(attrs \\ %{}),
    do: Map.merge(%{id: 1, slug: "line-a", title: "one", stage: "spec", awaiting: nil, blocking: nil}, Map.new(attrs))

  test "nil data renders a placeholder, no crash" do
    text = nil |> Workline.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "no worklines"
  end

  test "no open worklines renders the same placeholder" do
    text = %{worklines: []} |> Workline.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "no worklines"
  end

  test "renders each workline's slug and stage" do
    data = %{worklines: [w(slug: "line-a", stage: "spec"), w(id: 2, slug: "line-b", stage: "build")]}

    text = data |> Workline.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "line-a"
    assert text =~ "spec"
    assert text =~ "line-b"
    assert text =~ "build"
  end

  test "a gated workline shows who it awaits" do
    data = %{worklines: [w(awaiting: "andrew")]}
    text = data |> Workline.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "awaiting andrew"
  end

  test "a blocking check shows the warning glyph, cmd, and tail" do
    data = %{worklines: [w(blocking: %{cmd: "mix test", tail: "1 failure"})]}
    text = data |> Workline.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "⚠"
    assert text =~ "mix test"
    assert text =~ "1 failure"
  end

  test "a clean workline (no gate, no blocking) shows neither marker" do
    data = %{worklines: [w()]}
    text = data |> Workline.render(@rect) |> lines() |> Enum.join("\n")
    refute text =~ "awaiting"
    refute text =~ "⚠"
  end

  test "the selected row's slug washes :selected; the rest stay :normal" do
    data = %{worklines: [w(slug: "line-a"), w(id: 2, slug: "line-b")], selected: 1}
    rows = Workline.render(data, @rect)

    style_of = fn needle ->
      Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t == needle, do: s end) end)
    end

    assert style_of.("line-b") == :selected
    assert style_of.("line-a") == :normal
  end

  test "pick maps a row to focusing that thread; out-of-range and nil data are no-ops" do
    data = %{worklines: [w(id: 7, slug: "line-a")]}
    assert Workline.pick(data, @rect, 0) == {:focus_thread, 7}
    assert Workline.pick(data, @rect, 1) == nil
    assert Workline.pick(nil, @rect, 0) == nil
  end

  test "hints/1 declares the pane's footer verbs" do
    assert Aleph.Panel.hints(Workline, %{}) == [{"j/k", "worklines"}, {"⏎", "open"}]
  end
end
