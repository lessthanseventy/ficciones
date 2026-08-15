defmodule Aleph.Board do
  @moduledoc """
  Composes placed panels into one `Raxol.Terminal.ScreenBuffer` — the render half of
  the cockpit. A placement is `{panel_module, data, rect}`; the board asks each panel
  for its lines and writes them into the buffer at the rect's offset. The buffer is
  later handed to the termbox `Driver` to paint; here it is a pure, testable value.
  """
  alias Raxol.Terminal.ScreenBuffer

  @type placement :: {module(), term(), Aleph.Panel.rect()}

  @spec render([placement()], pos_integer(), pos_integer()) :: ScreenBuffer.t()
  def render(placements, width, height) do
    buffer = ScreenBuffer.new(width, height)

    Enum.reduce(placements, buffer, fn {panel, data, rect}, buf ->
      panel.render(data, rect)
      |> Enum.with_index()
      |> Enum.reduce(buf, fn {line, i}, b ->
        ScreenBuffer.write_string(b, rect.x, rect.y + i, line)
      end)
    end)
  end
end
