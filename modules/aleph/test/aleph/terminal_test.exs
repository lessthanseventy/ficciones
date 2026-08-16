defmodule Aleph.TerminalTest do
  @moduledoc """
  The embedded terminal (design §4) — a real PTY through Ghostty's VT engine, not a capture. These
  drive a live child and read its screen back, so they exercise the actual native loop.
  """
  use ExUnit.Case, async: true

  alias Aleph.Terminal

  test "runs a command in a real PTY, pings on output, reads the screen back with color" do
    {:ok, t} =
      Terminal.start_link(
        cmd: "/bin/bash",
        args: ["-c", "printf 'hi \\033[31mred\\033[0m done\\r\\n'; sleep 0.2"],
        cols: 40,
        rows: 4,
        notify: self()
      )

    # the cockpit repaints on this ping, not on a timer
    assert_receive {Terminal, ^t, :updated}, 2000
    # let the rest of the line land
    Process.sleep(120)

    rows = Terminal.cells(t)
    # reconstruct row 0's visible text from the cell grid (the render path reads cells, not snapshot)
    text =
      (Enum.at(rows, 0) || [])
      |> Enum.map_join(fn {g, _fg, _bg, _flags} -> if g == "", do: " ", else: g end)
      |> String.trim_trailing()

    assert text =~ "hi red done"

    # the ANSI red survives as a real RGB fg on the cells (a capture-pane view lost color)
    reds = rows |> List.flatten() |> Enum.filter(fn {g, fg, _bg, _flags} -> g == "r" and fg != nil end)
    assert reds != [], "expected the red run to carry an RGB foreground"
  end

  test "resize/3 does not crash the session (emulator + PTY both resized)" do
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    assert :ok = Terminal.resize(t, 80, 24)
    # still answering after the resize
    assert is_list(Terminal.cells(t))
  end

  test "render_state/1 gives the renderer everything at once: cells + a real cursor" do
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    state = Terminal.render_state(t)
    assert is_list(state.cells)
    # a cursor with a position + visibility so the embedded terminal shows where you type
    assert %{x: _, y: _, visible: _} = state.cursor
  end

  test "a {:pty_write, _} query response from the emulator is written back to the PTY, never dropped" do
    # cat echoes stdin, so if the query response reaches the PTY it comes back as screen output.
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    send(t, {:pty_write, "echoed\r\n"})
    assert_receive {Terminal, ^t, :updated}, 2000
    Process.sleep(80)

    text = t |> Terminal.cells() |> List.flatten() |> Enum.map_join(fn {g, _, _, _} -> g end)
    assert text =~ "echoed"
  end
end
