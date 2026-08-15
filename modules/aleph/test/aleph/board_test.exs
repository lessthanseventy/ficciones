defmodule Aleph.BoardTest do
  @moduledoc """
  The spike/slice-1 render proof: our panel render logic is correct, and it composes
  through raxol_terminal's ScreenBuffer without a TTY. Actual on-screen paint (buffer
  → termbox NIF) is the eye test, run in a real terminal.
  """
  use ExUnit.Case, async: true

  alias Raxol.Terminal.ScreenBuffer

  @roster [
    %{
      agent: "Sandra",
      thread_id: 1,
      thread_title: "review PR 329",
      workspace_ref: nil,
      warm?: true
    },
    %{
      agent: "Robert",
      thread_id: 2,
      thread_title: "triage inbox",
      workspace_ref: nil,
      warm?: false
    }
  ]

  test "roster panel renders one line per session, warmth marked" do
    rect = %{x: 0, y: 0, w: 40, h: 10}
    assert [sandra, robert] = Aleph.Panel.Roster.render(@roster, rect)
    assert String.starts_with?(sandra, "▸ Sandra · review PR 329")
    assert String.ends_with?(sandra, "· warm")
    refute String.contains?(robert, "warm")
  end

  test "panels clip to their rect (width and height)" do
    rect = %{x: 0, y: 0, w: 12, h: 1}
    assert [only] = Aleph.Panel.Roster.render(@roster, rect)
    assert String.length(only) <= 12
  end

  test "board composes panels into a raxol_terminal ScreenBuffer (render path proof)" do
    rect = %{x: 0, y: 0, w: 40, h: 10}
    buffer = Aleph.Board.render([{Aleph.Panel.Roster, @roster, rect}], 80, 24)
    refute is_nil(ScreenBuffer.get_cell(buffer, 0, 0))
  end
end
