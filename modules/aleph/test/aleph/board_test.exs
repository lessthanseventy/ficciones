# A one-row panel that renders whatever raw string it's given, for probing the paint boundary.
defmodule SanitizeProbe do
  @moduledoc false
  @behaviour Aleph.Panel

  @impl true
  def topics(_), do: []
  @impl true
  def render(text, _rect) when is_binary(text), do: [[{text, :normal}]]
end

defmodule Aleph.BoardTest do
  @moduledoc """
  The slice-1 render proof: the panel → styled-rows → composed-cells path is correct without a
  TTY. Actual on-screen paint (cells → termbox NIF) is the eye test, run in a real terminal.
  """
  use ExUnit.Case, async: true

  alias Aleph.Board
  alias Aleph.Panel
  alias Aleph.Panel.Border
  alias Aleph.Panel.Conversation
  alias Aleph.Panel.Dossier
  alias Aleph.Panel.Roster
  alias Aleph.Panel.Session
  alias Aleph.Panel.Spaces
  alias Aleph.Panel.StatusBar
  alias Aleph.Panel.ThreadList
  alias Aleph.View

  # Flatten a styled row to its text, for assertions.
  defp text(row), do: Enum.map_join(row, fn {t, _style} -> t end)

  @roster [
    %{agent: "Sandra", thread_id: 1, thread_title: "review PR 329", pane_ref: nil, warm?: true},
    %{agent: "Robert", thread_id: 2, thread_title: "triage inbox", pane_ref: nil, warm?: false}
  ]

  @threads [
    %Funes.Thread{id: 1, title: "review PR 329", state: "open"},
    %Funes.Thread{id: 2, title: "triage inbox", state: "open"}
  ]

  defp reads(overrides \\ %{}) do
    Map.merge(
      %{
        active_key: :sessions,
        focused_id: 1,
        focused_title: "review PR 329",
        roster: @roster,
        threads: @threads,
        scope: nil,
        chatter: [],
        session: :no_session
      },
      overrides
    )
  end

  describe "panels render styled rows" do
    test "roster: header, one row per session, warmth marked" do
      rect = %{x: 0, y: 0, w: 40, h: 10}
      assert [header, _blank, sandra, robert] = Roster.render(@roster, rect)
      assert text(header) == "IN FLIGHT"
      assert text(sandra) =~ "Sandra"
      assert text(sandra) =~ "review PR 329"
      assert text(sandra) =~ "●"
      assert text(robert) =~ "○"
    end

    test "thread list highlights the selected thread across the column" do
      rect = %{x: 0, y: 0, w: 30, h: 10}
      data = %{threads: @threads, selected_id: 1}
      rows = ThreadList.render(data, rect)
      selected = Enum.find(rows, &(text(&1) =~ "▸"))
      other = Enum.find(rows, &(text(&1) =~ "·" and text(&1) =~ "triage"))

      assert text(selected) =~ "review PR 329"
      # Selected row is padded with the highlight style out to the column width.
      assert Enum.any?(selected, fn {_t, style} -> style == :selected end)
      refute Enum.any?(other, fn {_t, style} -> style == :selected end)
    end

    test "thread list annotates a thread that has a live agent (merged IN FLIGHT)" do
      rect = %{x: 0, y: 0, w: 40, h: 10}

      roster = [
        %{agent: "Carl", thread_id: 1, thread_title: "review PR 329", pane_ref: nil, warm?: true}
      ]

      data = %{threads: @threads, roster: roster, selected_id: 2}
      rows = ThreadList.render(data, rect)

      live = Enum.find(rows, &(text(&1) =~ "review PR 329"))
      idle = Enum.find(rows, &(text(&1) =~ "triage"))

      # the live thread shows its warm dot and agent (pink); the idle one shows neither
      assert text(live) =~ "●"
      assert text(live) =~ "Carl"
      assert Enum.any?(live, fn {t, s} -> s == :accent and t =~ "Carl" end)
      refute text(idle) =~ "Carl"
    end

    test "spaces picker marks the active space" do
      rows =
        Spaces.render(%{spaces: Aleph.Space.all(), active_key: :comms}, %{
          x: 0,
          y: 0,
          w: 20,
          h: 10
        })

      active = Enum.find(rows, &(text(&1) =~ "▸"))
      assert text(active) =~ "Comms"
    end

    test "dossier renders sections from an in_scope map, honest about empties and cuts" do
      # learnings/shipped/blockers are each %{shown, more} (funes Board R3): a cap
      # is always rendered WITH its count — a cut without a count lies.
      scope = %{
        north_star: "ship the board",
        lead: "Sandra",
        learnings: %{shown: [%{text: "termbox compiles"}], more: 2},
        blockers: %{shown: [], more: 0},
        shipped: %{shown: [], more: 0},
        chatter: []
      }

      rows = Dossier.render(scope, %{x: 0, y: 0, w: 40, h: 40})
      joined = Enum.map_join(rows, "\n", &text/1)
      assert joined =~ "NORTH STAR"
      assert joined =~ "ship the board"
      assert joined =~ "LEARNINGS"
      assert joined =~ "termbox compiles"
      # the cut is counted, never silent
      assert joined =~ "+2 more"
      # empty section keeps its shape with a dim em-dash, never an invented value
      assert joined =~ "—"
    end

    test "session placeholder when no tmux pane" do
      rows = Session.render(:no_session, %{x: 0, y: 0, w: 40, h: 10})
      assert Enum.map_join(rows, "\n", &text/1) =~ "no live tmux session"
    end
  end

  describe "status bar" do
    defp status(overrides \\ %{}) do
      Map.merge(
        %{space: "Sessions", thread: "flaky test hunt", thread_count: 3, live_count: 1},
        overrides
      )
    end

    test "info line shows the space, thread, and global counts" do
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      joined = text(info)
      assert joined =~ "Sessions"
      assert joined =~ "flaky test hunt"
      # the underused right side now carries global state
      assert joined =~ "3 threads"
      assert joined =~ "1 live"
    end

    test "hints line is always present on the bottom row" do
      assert [_info, hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      joined = text(hints)
      assert joined =~ "quit"
      assert joined =~ "thread"
    end

    test "the info line fills the width without flooding it with a chip background" do
      w = 120
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: w, h: 2})
      # padded to the full width...
      assert Panel.row_width(info) == w
      # ...but the wide gap is neutral, never a chip/selection background (the old full-bar flood)
      refute Enum.any?(info, fn {t, s} ->
               s != :normal and String.trim(t) == "" and String.length(t) >= 3
             end)
    end

    test "the space renders as a discrete tab chip" do
      assert [info, _hints] = StatusBar.render(status(), %{x: 0, y: 0, w: 120, h: 2})
      chip = Enum.find(info, fn {t, s} -> s == :tab and t =~ "Sessions" end)
      assert chip, "space should render as a :tab chip"
    end
  end

  describe "border box" do
    test "draws a rounded box framing the whole rect" do
      rows = Border.render(nil, %{x: 0, y: 0, w: 6, h: 4})
      assert length(rows) == 4
      assert text(Enum.at(rows, 0)) == "╭────╮"
      assert text(Enum.at(rows, 3)) == "╰────╯"
      mid = Enum.at(rows, 1)
      assert text(mid) == "│    │"
      # the frame is drawn in the separator style; the interior is neutral
      assert {"│", :separator} = hd(mid)
    end

    test "degenerates safely below 2×2" do
      assert Border.render(nil, %{x: 0, y: 0, w: 1, h: 5}) == []
    end
  end

  describe "clip" do
    test "clips rows to height and each row to width" do
      rows = [Panel.line("a very long header line", :header)]
      assert [clipped] = Panel.clip(rows, %{x: 0, y: 0, w: 5, h: 1})
      assert String.length(text(clipped)) == 5
    end
  end

  describe "view composition" do
    test "sessions space: picker, tmux surface, a box per section, status bar — all in bounds" do
      placements = View.compose(reads(), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)

      assert Spaces in mods
      assert Session in mods
      assert Dossier in mods
      assert StatusBar in mods
      # every section gets its own bordered box (switcher, thread list, session, dossier)
      content_panels = Enum.reject(mods, &(&1 in [Border, StatusBar]))
      assert Enum.count(mods, &(&1 == Border)) == length(content_panels)
      assert length(content_panels) >= 4

      Enum.each(placements, fn {_m, _d, r} ->
        assert r.x >= 0 and r.y >= 0
        assert r.x + r.w <= 120
        assert r.y + r.h <= 40
      end)
    end

    test "content sits inside its column box, not against the frame" do
      placements = View.compose(reads(), 120, 40)
      {_m, _d, list_rect} = Enum.find(placements, fn {m, _d, _r} -> m == ThreadList end)
      # the thread list is inset from the left frame — padded, not jammed to x=0
      assert list_rect.x >= 2
    end

    test "comms space swaps the center surface to the conversation" do
      placements = View.compose(reads(%{active_key: :comms}), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)
      assert Conversation in mods
      refute Session in mods
    end

    test "sessions space shows a thread navigator so up/down selection is visible" do
      placements = View.compose(reads(%{focused_id: 2}), 120, 40)
      thread_list = Enum.find(placements, fn {m, _d, _r} -> m == ThreadList end)

      assert thread_list,
             "Sessions space needs a visible ThreadList to navigate; focus was invisible"

      {_m, data, _r} = thread_list
      # the navigator's cursor is the focused thread — what up/down moves
      assert data.selected_id == 2
    end
  end

  describe "responsive layout" do
    defp box_xs(placements) do
      placements
      |> Enum.filter(fn {m, _d, _r} -> m == Border end)
      |> Enum.map(fn {_m, _d, r} -> r.x end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    test "a wide viewport lays out three columns" do
      xs = reads() |> View.compose(140, 40) |> box_xs()
      # three distinct column x-offsets (left at 0, center, right)
      assert length(xs) == 3
      assert 0 in xs
    end

    test "a narrow viewport collapses to a single column" do
      xs = reads() |> View.compose(50, 40) |> box_xs()
      # every section box sits in one column at x=0
      assert xs == [0]
    end

    test "the same sections are present in both layouts" do
      wide = reads() |> View.compose(140, 40) |> Enum.map(fn {m, _d, _r} -> m end)
      narrow = reads() |> View.compose(50, 40) |> Enum.map(fn {m, _d, _r} -> m end)
      assert Enum.sort(Enum.uniq(wide)) == Enum.sort(Enum.uniq(narrow))
    end
  end

  describe "board composes cells" do
    test "a placement produces cells at the rect origin" do
      rect = %{x: 3, y: 2, w: 40, h: 10}
      cells = Board.compose([{Roster, @roster, rect}], 80, 24)
      assert Enum.any?(cells, &(&1.x == 3 and &1.y == 2))
      # every cell carries a codepoint and colours
      assert Enum.all?(cells, &(is_integer(&1.ch) and is_integer(&1.fg) and is_integer(&1.bg)))
    end

    test "control bytes in panel content are never emitted to the terminal" do
      # A stray ESC (27) or other C0/C1 control byte from a captured tmux pane would, painted
      # raw, be read by the terminal as the start of an escape sequence and shift the whole
      # screen's colours. The paint boundary must neutralise them to a space (0x20).
      rect = %{x: 0, y: 0, w: 20, h: 3}
      panel = {SanitizeProbe, "a\e[31mb\tc", rect}

      chars = [panel] |> Board.compose(80, 24) |> Enum.map(& &1.ch)

      refute 27 in chars, "ESC leaked into a cell"
      refute 9 in chars, "TAB leaked into a cell"
      assert Enum.all?(chars, &(&1 >= 32 and &1 != 127)), "a control byte reached the terminal"
      # printable characters survive
      assert ?a in chars and ?b in chars and ?c in chars
    end
  end
end
