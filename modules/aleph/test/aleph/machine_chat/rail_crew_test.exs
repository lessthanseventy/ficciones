defmodule Aleph.MachineChat.RailCrewTest do
  @moduledoc "The THREADS and CREW rails render pre-annotated data; selection stays visible."
  use ExUnit.Case, async: true

  alias Aleph.MachineChat.Crew
  alias Aleph.MachineChat.Rail

  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, "", fn {t, _s} -> t end) end)

  defp row(id, title, opts \\ []) do
    %{
      id: id,
      title: title,
      state: Keyword.get(opts, :state, "open"),
      status: Keyword.get(opts, :status, :none),
      unread: Keyword.get(opts, :unread, 0)
    }
  end

  describe "Rail.render/2" do
    test "glyphs by status/state, unread badge, selection styled" do
      rows = [
        row(1, "⌂ Tlön", status: :live),
        row(2, "fix the bug", status: :working, unread: 3),
        row(3, "old thing", state: "closed")
      ]

      rendered = Rail.render(%{rows: rows, selected_id: 1}, %{x: 0, y: 0, w: 26, h: 20})
      body = texts(rendered)

      assert Enum.at(body, 0) =~ "THREADS"
      assert Enum.any?(body, &(&1 =~ "⌂ Tlön"))
      assert Enum.any?(body, &(&1 =~ "fix the bug" and &1 =~ "•3"))
      assert Enum.any?(body, &(&1 =~ "✓ old thing"))

      # the selected row carries the :selected style on its title
      selected_runs = rendered |> Enum.flat_map(& &1) |> Enum.filter(fn {_t, s} -> s == :selected end)
      assert [{t, _}] = selected_runs
      assert t =~ "Tlön"
    end

    test "a long title clips to the rail width" do
      rows = [row(1, String.duplicate("x", 60))]
      [_, _, only] = Rail.render(%{rows: rows, selected_id: 1}, %{x: 0, y: 0, w: 20, h: 10})
      assert only |> Enum.map_join("", fn {t, _} -> t end) |> String.length() <= 20
    end

    test "windowing keeps a deep selection visible" do
      rows = for i <- 1..30, do: row(i, "thread #{i}")
      rendered = Rail.render(%{rows: rows, selected_id: 25}, %{x: 0, y: 0, w: 26, h: 10})
      assert Enum.any?(texts(rendered), &(&1 =~ "thread 25"))
    end
  end

  describe "Crew.render/2" do
    test "leaves counter + per-coworker archetype, presence, seat, and driver" do
      data = %{
        leaves: {2, 6},
        coworkers: [
          %{name: "tertius", archetype: :surveyor, model: %{model: "glm-5.2"}, harness: :pi, status: :live, seat: nil},
          %{
            name: "vera",
            archetype: :reviewer,
            model: %{model: "claude-sonnet-5"},
            harness: :claude_code,
            status: :working,
            seat: "fix the bug"
          }
        ]
      }

      body = texts(Crew.render(data, %{x: 0, y: 0, w: 26, h: 30}))

      assert Enum.at(body, 0) =~ "CREW"
      assert Enum.at(body, 0) =~ "leaves 2/6"
      assert Enum.any?(body, &(&1 =~ "tertius" and &1 =~ "surveyor"))
      assert Enum.any?(body, &(&1 =~ "idle"))
      assert Enum.any?(body, &(&1 =~ "working" and &1 =~ "fix the bug"))
      assert Enum.any?(body, &(&1 =~ "glm-5.2" and &1 =~ "pi"))
      assert Enum.any?(body, &(&1 =~ "claude-sonnet-5" and &1 =~ "· claude"))
    end
  end
end
