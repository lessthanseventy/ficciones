defmodule Aleph.Panel.StatusBarTest do
  # The contextual footer (design 2026-08-23): mode segment (TERM/NAV/LOCK's own verbs) → space
  # segment (world-only post/task/driver) → the focused pane's own hints. Keyed on world?, never
  # the space label — the stale "Tlön"-keyed table died with this.
  use ExUnit.Case, async: true

  alias Aleph.Panel.StatusBar

  defp rect, do: %{x: 0, y: 0, w: 120, h: 2}

  defp base(over) do
    Map.merge(
      %{
        space: "Tlön",
        thread: nil,
        thread_count: 0,
        live_count: 0,
        input: nil,
        flash: nil,
        leader_pending?: false,
        focus: nil,
        mode: nil,
        world?: false,
        lock?: false,
        pane_hints: []
      },
      over
    )
  end

  test "TERM mode: the mode segment names the Alt door and the nav toggle" do
    [_info, hints] = StatusBar.render(base(%{mode: :term, world?: true}), rect())
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+#"
    assert line =~ "^␣"
    refute line =~ "space"
  end

  test "NAV mode: mode + space verbs + the focused pane's own verbs" do
    data = base(%{mode: :nav, world?: true, pane_hints: [{"j/k", "commits"}, {"⏎", "diff"}]})
    [_info, hints] = StatusBar.render(data, rect())
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+0"
    assert line =~ "c post"
    assert line =~ "n task"
    assert line =~ "m driver"
    assert line =~ "j/k commits"
    assert line =~ "⏎ diff"
  end

  test "LOCK mode: the unlock chord alone, and a warning chip" do
    [info, hints] = StatusBar.render(base(%{mode: :lock, world?: true}), rect())
    assert {" LOCK ", :stat_warn} in info
    line = Enum.map_join(hints, fn {t, _} -> t end)
    assert line =~ "Alt+g unlock"
    refute line =~ "post"
  end

  test "a non-world space (mode nil) keeps the shared leader table" do
    [_info, hints] = StatusBar.render(base(%{space: "Orbis"}), rect())
    assert Enum.map_join(hints, fn {t, _} -> t end) =~ "^␣n new"
  end

  test "hints keyed on world-ness, never the label: a renamed world still gets world hints" do
    data = base(%{space: "Uqbar", mode: :nav, world?: true})
    [_info, hints] = StatusBar.render(data, rect())
    assert Enum.map_join(hints, fn {t, _} -> t end) =~ "c post"
  end
end
