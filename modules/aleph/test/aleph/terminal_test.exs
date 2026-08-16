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

  describe "wheel/5 — the pure routing seams" do
    test "wheel_button maps up→:four (xterm button 4), down→:five (button 5)" do
      assert Terminal.wheel_button(:up) == :four
      assert Terminal.wheel_button(:down) == :five
    end

    test "scroll_delta: up is negative (into scrollback history), down is positive (newer)" do
      assert Terminal.scroll_delta(:up, 3) == -3
      assert Terminal.scroll_delta(:down, 3) == 3
    end
  end

  describe "wheel/5 — the live branch" do
    test "scrolls the VT scrollback when the program hasn't enabled mouse tracking" do
      # 30 lines into a 4-row terminal ⇒ scrollback. The child stays alive long enough to scroll.
      {:ok, t} =
        Terminal.start_link(
          cmd: "/bin/bash",
          args: ["-c", "for i in $(seq 1 30); do printf 'line %d\n' $i; done; sleep 1"],
          cols: 40,
          rows: 4,
          notify: self()
        )

      assert_receive {Terminal, ^t, :updated}, 2000
      Process.sleep(250)

      base = Terminal.render_state(t).scrollbar.offset
      assert :scrolled = Terminal.wheel(t, :up, 3, 0, 0)
      up = Terminal.render_state(t).scrollbar.offset
      assert up != base
      # wheel back down by the same amount restores the viewport
      assert :scrolled = Terminal.wheel(t, :down, 3, 0, 0)
      assert Terminal.render_state(t).scrollbar.offset == base
    end

    test "forwards a mouse event to the PTY when the program enabled mouse tracking" do
      # A mouse-aware TUI enables tracking by writing \e[?1000h to its stdout; the PTY delivers that
      # to the emulator as :data. Send it directly (the realistic path) and assert the branch taken.
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      send(t, {:data, "\e[?1000h"})
      assert_receive {Terminal, ^t, :updated}, 1000

      assert Terminal.mouse_modes(t).tracking
      assert :forwarded = Terminal.wheel(t, :up, 3, 5, 5)
    end
  end
end
