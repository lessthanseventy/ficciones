# A one-row panel that renders whatever raw string it's given, for probing the paint boundary.
defmodule SanitizeProbe do
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

  alias Aleph.{Board, Panel, View}

  alias Aleph.Panel.{
    Conversation,
    Dossier,
    Roster,
    Rule,
    Session,
    StatusBar,
    ThreadList,
    Workspaces
  }

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
        active_key: :terminal,
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

    test "workspaces picker marks the active workspace" do
      rows =
        Workspaces.render(%{workspaces: Aleph.Workspace.all(), active_key: :chat}, %{
          x: 0,
          y: 0,
          w: 20,
          h: 10
        })

      active = Enum.find(rows, &(text(&1) =~ "▸"))
      assert text(active) =~ "Chat"
    end

    test "dossier renders sections from an in_scope map, honest about empties" do
      scope = %{
        north_star: "ship the board",
        lead: "Sandra",
        learnings: [%{text: "termbox compiles"}],
        blockers: %{shown: [], more: 0},
        shipped: [],
        chatter: []
      }

      rows = Dossier.render(scope, %{x: 0, y: 0, w: 40, h: 40})
      joined = Enum.map_join(rows, "\n", &text/1)
      assert joined =~ "NORTH STAR"
      assert joined =~ "ship the board"
      assert joined =~ "LEARNINGS"
      assert joined =~ "termbox compiles"
      # empty section keeps its shape with a dim em-dash, never an invented value
      assert joined =~ "—"
    end

    test "session placeholder when no tmux pane" do
      rows = Session.render(:no_session, %{x: 0, y: 0, w: 40, h: 10})
      assert Enum.map_join(rows, "\n", &text/1) =~ "no live tmux session"
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
    test "terminal workspace: picker, tmux surface, two rules, status bar — all in bounds" do
      placements = View.compose(reads(), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)

      assert Workspaces in mods
      assert Session in mods
      assert Dossier in mods
      assert StatusBar in mods
      assert Enum.count(mods, &(&1 == Rule)) == 2

      Enum.each(placements, fn {_m, _d, r} ->
        assert r.x >= 0 and r.y >= 0
        assert r.x + r.w <= 120
        assert r.y + r.h <= 40
      end)
    end

    test "chat workspace swaps the center surface to the conversation" do
      placements = View.compose(reads(%{active_key: :chat}), 120, 40)
      mods = Enum.map(placements, fn {m, _d, _r} -> m end)
      assert Conversation in mods
      refute Session in mods
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

      chars = Board.compose([panel], 80, 24) |> Enum.map(& &1.ch)

      refute 27 in chars, "ESC leaked into a cell"
      refute 9 in chars, "TAB leaked into a cell"
      assert Enum.all?(chars, &(&1 >= 32 and &1 != 127)), "a control byte reached the terminal"
      # printable characters survive
      assert ?a in chars and ?b in chars and ?c in chars
    end
  end
end
