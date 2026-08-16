defmodule Aleph.Board do
  @moduledoc """
  The render half of the cockpit: flatten placed panels into a list of styled cells, then paint
  them. `compose/3` is a pure, testable value (no TTY) — each panel's styled rows are walked into
  `%{x, y, ch, fg, bg}` cells at the panel's rect offset, semantic styles resolved to truecolor
  by `Aleph.Style`. `paint/1` blits that list through the termbox2 NIF (output-only; input +
  resize come from `Raxol.Terminal.Driver`, see `Aleph.Cockpit`).
  """
  alias Aleph.{Panel, Style}

  @type placement :: {module(), term(), Panel.rect()}
  @type cell :: %{
          x: non_neg_integer(),
          y: non_neg_integer(),
          ch: char(),
          fg: integer(),
          bg: integer()
        }

  @spec compose([placement()], pos_integer(), pos_integer()) :: [cell()]
  def compose(placements, _width, _height) do
    Enum.flat_map(placements, fn {panel, data, rect} ->
      panel.render(data, rect)
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, i} -> row_cells(row, rect.x, rect.y + i) end)
    end)
  end

  # Walk a row's runs left-to-right, emitting one cell per grapheme with the run's colours.
  defp row_cells(row, x0, y) do
    {cells, _x} =
      Enum.reduce(row, {[], x0}, fn {text, style}, {acc, x} ->
        {fg, bg} = Style.fg_bg(style)

        {chars, next_x} =
          text
          |> String.graphemes()
          |> Enum.map_reduce(x, fn g, cx ->
            {%{x: cx, y: y, ch: codepoint(g), fg: fg, bg: bg}, cx + 1}
          end)

        {[chars | acc], next_x}
      end)

    cells |> Enum.reverse() |> List.flatten()
  end

  # Panel content can carry raw bytes (a tmux `capture-pane` snapshot of a program's output).
  # Painting a C0/C1 control byte or DEL straight to the terminal would let it be read as the
  # start of an escape sequence — a stray ESC shifts the whole screen's colours. Neutralise them
  # to a space here, at the one boundary every cell passes through, so no panel can leak one.
  defp codepoint(grapheme) do
    cp = grapheme |> String.to_charlist() |> hd()
    if cp < 0x20 or (cp >= 0x7F and cp <= 0x9F), do: 0x20, else: cp
  end

  @doc "Blit composed cells to the real screen via termbox2. Assumes `tb_init` already ran."
  @spec paint([cell()]) :: :ok
  def paint(cells) do
    :termbox2_nif.tb_clear()

    Enum.each(cells, fn %{x: x, y: y, ch: ch, fg: fg, bg: bg} ->
      :termbox2_nif.tb_set_cell(x, y, ch, fg, bg)
    end)

    :termbox2_nif.tb_present()
    :ok
  end
end
