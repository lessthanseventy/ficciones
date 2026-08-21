defmodule Aleph.Panel.Terminal do
  @moduledoc """
  The center column: a REAL embedded terminal (design §4). Renders an `Aleph.Terminal`'s
  `render_state` — Ghostty's live cell grid — as truecolor runs, each cell carrying its own RGB
  from the VT engine (not a semantic palette). The cursor cell is inverted so you can see where
  you type, and the `inverse` attribute (SGR 7) swaps fg/bg like a real terminal.

  Data is a `render_state` map (`%{cells, cursor, foreground, background}`) or `:no_session`.
  Pure: a render_state in → styled rows out, no TTY. The cockpit blits these through `Aleph.Board`,
  which already paints 24-bit colour.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, pad: 3]
  import Bitwise

  # Fallback colours when the emulator reports nil (use the terminal-native pair).
  @default_fg 0xC5C8C6
  @default_bg 0x000000
  @inverse_bit 32

  # Claude Code paints its theme `background` token — a deliberately garish "you should never see
  # this" cyan (dark UI: rgb(0,204,204); light: rgb(0,153,153)) — as the EXPLICIT per-cell bg on
  # queued/injected message rows (your own input, cross-thread funes messages). The VT stores it
  # faithfully, so without neutralising it those rows blit as cyan under a phosphor theme. Remap the
  # sentinel to the panel's own default so they read like the rest of the screen. It's not a real
  # background choice any harness means to show — matching the value is the only signal aleph gets.
  @bg_sentinels [0x00CCCC, 0x009999]

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

    cell_rows =
      cells
      |> Enum.with_index()
      |> Enum.map(fn {row, y} -> cell_runs(row, y, cursor, default_fg, default_bg) end)

    render_state[:tabs]
    |> tab_rows(rect.w)
    |> Kernel.++(cell_rows)
    |> Aleph.Panel.clip(rect)
  end

  # When the panel carries a window list (the Tlön workspace), aleph draws its OWN tab strip as the
  # header row — tmux's status bar is off, so this is the only window chrome. A Sessions coworker
  # terminal carries no tabs and renders edge-to-edge. The active window is `:selected` (the picker's
  # highlight), the rest `:dim`.
  defp tab_rows(tabs, w) when is_list(tabs) and tabs != [] do
    [pad(Enum.map(tabs, &tab_run/1), w, :normal)]
  end

  defp tab_rows(_tabs, _w), do: []

  defp tab_run(t), do: {tab_label(t), if(t.active?, do: :selected, else: :dim)}
  defp tab_label(t), do: " #{t.name} "

  @doc """
  Hit-test the tab strip a click landed on: the tab whose ` name ` segment contains column `x`
  (0-based within the panel), or nil past the last tab. Shares `tab_label/1` with the render so the
  clickable regions can't drift from what's drawn.
  """
  def tab_at_x(tabs, x) do
    tabs
    |> Enum.reduce_while(0, fn t, start ->
      next = start + String.length(tab_label(t))
      if x >= start and x < next, do: {:halt, t}, else: {:cont, next}
    end)
    |> case do
      %{} = tab -> tab
      _ -> nil
    end
  end

  # One run per cell — its own RGB. Board.row_cells emits a cell per grapheme, so per-cell runs are
  # exactly right for a terminal, where adjacent cells routinely differ in colour.
  defp cell_runs(row, y, cursor, default_fg, default_bg) do
    row
    |> Enum.with_index()
    |> Enum.map(fn {{grapheme, fg, bg, flags}, x} ->
      char = if grapheme in ["", nil], do: " ", else: grapheme
      fg = rgb_int(fg) || default_fg
      bg = neutralize_sentinel(rgb_int(bg) || default_bg, default_bg)

      # inverse video (SGR 7) swaps, and the cursor cell inverts on top of that.
      {fg, bg} = if band(flags, @inverse_bit) == 0, do: {fg, bg}, else: {bg, fg}
      {fg, bg} = if cursor_at?(cursor, x, y), do: {bg, fg}, else: {fg, bg}

      {char, {:rgb, fg, bg}}
    end)
  end

  # A cell bg equal to Claude Code's `background` sentinel (see @bg_sentinels) reads as the panel
  # default; every other colour passes through untouched.
  defp neutralize_sentinel(bg, default_bg) when bg in @bg_sentinels, do: default_bg
  defp neutralize_sentinel(bg, _default_bg), do: bg

  defp cursor_at?(%{visible: true, x: cx, y: cy}, x, y), do: cx == x and cy == y
  defp cursor_at?(_cursor, _x, _y), do: false

  defp rgb_int(nil), do: nil
  defp rgb_int({r, g, b}), do: r * 65_536 + g * 256 + b
end
