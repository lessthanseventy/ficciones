defmodule Aleph.Panel.CrewTest do
  @moduledoc "The CREW pane: pure assembly (roster ⋈ windows ⋈ leads ⋈ thinking) + render."
  use ExUnit.Case, async: true

  alias Aleph.Panel.Crew

  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, "", fn {t, _s} -> t end) end)

  describe "coworkers/6" do
    @now 1_000_000
    @roster [
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "builder", "name" => "hronir"}
    ]
    @titles %{7 => "fix the bug", 9 => "write the doc"}

    defp by_name(coworkers, name), do: Enum.find(coworkers, &(&1.name == name))

    test "a coworker with no window is off; a quiet window is idle" do
      windows = [%{name: "tertius", thread_id: nil, activity: @now - 600}]
      coworkers = Crew.coworkers(@roster, windows, %{}, @titles, %{}, @now)

      assert %{status: :live, seat: nil, archetype: :surveyor} = by_name(coworkers, "tertius")
      assert %{status: :none, seat: nil} = by_name(coworkers, "hronir")
    end

    test "recent activity on a led leaf reads as working, seated on that thread" do
      windows = [
        %{name: "hronir", thread_id: nil, activity: @now - 600},
        %{name: "t7", thread_id: 7, activity: @now - 2}
      ]

      coworkers = Crew.coworkers(@roster, windows, %{"hronir-machine" => [7]}, @titles, %{}, @now)

      assert %{status: :working, seat: "fix the bug"} = by_name(coworkers, "hronir")
    end

    test "a declared thinking beats the tmux inference and seats the declared thread" do
      windows = [%{name: "hronir", thread_id: nil, activity: @now - 2}]
      thinking = %{9 => %{"hronir-machine" => @now - 1}}

      coworkers = Crew.coworkers(@roster, windows, %{}, @titles, thinking, @now)

      assert %{status: :thinking, seat: "write the doc"} = by_name(coworkers, "hronir")
    end

    test "profile fields ride along; an unknown archetype drops" do
      roster = @roster ++ [%{"archetype" => "gardener", "name" => "x"}]
      coworkers = Crew.coworkers(roster, [], %{}, %{}, %{}, @now)

      assert length(coworkers) == 2
      assert %{harness: harness, model: _model} = by_name(coworkers, "hronir")
      assert harness
    end
  end

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

    assert Enum.at(body, 0) =~ "leaves 2/6"
    assert Enum.any?(body, &(&1 =~ "tertius" and &1 =~ "surveyor"))
    assert Enum.any?(body, &(&1 =~ "idle"))
    assert Enum.any?(body, &(&1 =~ "working" and &1 =~ "fix the bug"))
    assert Enum.any?(body, &(&1 =~ "glm-5.2" and &1 =~ "pi"))
    assert Enum.any?(body, &(&1 =~ "claude-sonnet-5" and &1 =~ "· claude"))
  end

  test "a declared thinking renders the ⋯ glyph in accent" do
    data = %{
      leaves: {0, 6},
      coworkers: [
        %{
          name: "hronir",
          archetype: :builder,
          model: nil,
          harness: :claude_code,
          status: :thinking,
          seat: "write the doc"
        }
      ]
    }

    rendered = Crew.render(data, %{x: 0, y: 0, w: 26, h: 30})
    body = texts(rendered)

    assert Enum.any?(body, &(&1 =~ "⋯" and &1 =~ "thinking" and &1 =~ "write the"))
    accents = rendered |> Enum.flat_map(& &1) |> Enum.filter(fn {_t, s} -> s == :accent end)
    assert Enum.any?(accents, fn {t, _s} -> t =~ "⋯" end)
  end

  test "rows clip to the rect" do
    coworkers =
      for i <- 1..20 do
        %{name: "cw#{i}", archetype: :builder, model: nil, harness: :pi, status: :none, seat: nil}
      end

    rendered = Crew.render(%{leaves: {0, 6}, coworkers: coworkers}, %{x: 0, y: 0, w: 12, h: 8})
    assert length(rendered) <= 8
    assert Enum.all?(texts(rendered), &(String.length(&1) <= 12))
  end

  test "nil data renders nothing" do
    assert Crew.render(nil, %{x: 0, y: 0, w: 20, h: 10}) == []
  end
end
