defmodule Aleph.Panel.Terminal do
  @moduledoc """
  The center column: a REAL embedded terminal (design §4). Renders an `Aleph.Terminal`'s
  `render_state` — Ghostty's live cell grid — as truecolor runs, each cell carrying its own RGB
  from the VT engine (not a semantic palette). The cursor cell is inverted so you can see where
  you type, and the `inverse` attribute (SGR 7) swaps fg/bg like a real terminal.

  Renders edge-to-edge — no header row. The Tlön workspace's window strip (once drawn here as row
  0) is now `Aleph.Panel.WindowBar`, a standalone bordered panel `Aleph.View.compose/3` places
  above this one; a Sessions coworker terminal never had a strip and is unaffected.

  Data is a `render_state` map (`%{cells, cursor, foreground, background}`) or `:no_session`.
  Pure: a render_state in → styled rows out, no TTY. The cockpit blits these through `Aleph.Board`,
  which already paints 24-bit colour.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2]
  import Bitwise

  # Fallback colours when the emulator reports nil (use the terminal-native pair).
  @default_fg 0xC5C8C6
  @default_bg 0x000000
  @inverse_bit 32

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(:no_session, rect) do
    Aleph.Panel.clip([line("no live session — Enter to spawn one here", :dim)], rect)
  end

  def render(%{cells: cells} = render_state, rect) do
    default_fg = rgb_int(render_state[:foreground]) || @default_fg
    default_bg = rgb_int(render_state[:background]) || @default_bg
    cursor = render_state[:cursor] || %{visible: false}

    cells
    |> Enum.with_index()
    |> Enum.map(fn {row, y} -> cell_runs(row, y, cursor, default_fg, default_bg) end)
    |> Aleph.Panel.clip(rect)
  end

  # One run per cell — its own RGB. Board.row_cells emits a cell per grapheme, so per-cell runs are
  # exactly right for a terminal, where adjacent cells routinely differ in colour.
  defp cell_runs(row, y, cursor, default_fg, default_bg) do
    row
    |> Enum.with_index()
    |> Enum.map(fn {{grapheme, fg, bg, flags}, x} ->
      char = if grapheme in ["", nil], do: " ", else: grapheme
      fg = rgb_int(fg) || default_fg
      bg = rgb_int(bg) || default_bg

      # inverse video (SGR 7) swaps, and the cursor cell inverts on top of that.
      {fg, bg} = if band(flags, @inverse_bit) == 0, do: {fg, bg}, else: {bg, fg}
      {fg, bg} = if cursor_at?(cursor, x, y), do: {bg, fg}, else: {fg, bg}

      {char, {:rgb, fg, bg}}
    end)
  end

  defp cursor_at?(%{visible: true, x: cx, y: cy}, x, y), do: cx == x and cy == y
  defp cursor_at?(_cursor, _x, _y), do: false

  defp rgb_int(nil), do: nil
  defp rgb_int({r, g, b}), do: r * 65_536 + g * 256 + b
end
