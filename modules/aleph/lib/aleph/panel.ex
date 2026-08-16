defmodule Aleph.Panel do
  @moduledoc """
  A panel is a component; a view is a composition of panels; nothing is a prebaked
  full-screen template (design §3). A panel is a **thin view over a funes read model**
  and holds no logic of its own:

    - `topics/1` — the funes Bus topics whose events should re-render this panel.
    - `render/2` — turn the panel's data into styled rows, clipped to its rect.

  A panel renders **styled rows**: `render/2` returns `[row]`, where a `row` is a list of
  `{text, style}` runs (`style` a semantic atom resolved by `Aleph.Style`). Rows are plain
  data — a panel is a pure function `(funes read, rect) → rows`, so the whole render path is
  headlessly testable and the same panel can later paint in a LiveView (§7).
  """

  @type style :: atom()
  @type run :: {String.t(), style()}
  @type row :: [run()]
  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), w: pos_integer(), h: pos_integer()}

  @doc "The funes Bus topics whose events should re-render this panel (may depend on assigns like the focused thread)."
  @callback topics(assigns :: map()) :: [String.t()]

  @doc "Render the panel's data into styled rows, clipped to the rect."
  @callback render(data :: term(), rect()) :: [row()]

  @doc "A one-run row in a given style — the common case."
  @spec line(String.t(), style()) :: row()
  def line(text, style \\ :normal), do: [{text, style}]

  @doc "A blank spacer row."
  @spec blank() :: row()
  def blank, do: []

  @doc """
  Clip rows to a rect: at most `h` rows, each truncated to `w` graphemes across its runs.
  Truncation walks runs left-to-right, keeping whole runs until the width budget is spent
  and slicing the run that straddles the edge.
  """
  @spec clip([row()], rect()) :: [row()]
  def clip(rows, %{w: w, h: h}) do
    rows
    |> Enum.take(h)
    |> Enum.map(&clip_row(&1, w))
  end

  defp clip_row(_runs, w) when w <= 0, do: []

  defp clip_row(runs, w) do
    {kept, _left} =
      Enum.reduce_while(runs, {[], w}, fn {text, style}, {acc, left} ->
        len = String.length(text)

        cond do
          left <= 0 -> {:halt, {acc, 0}}
          len <= left -> {:cont, {[{text, style} | acc], left - len}}
          true -> {:halt, {[{String.slice(text, 0, left), style} | acc], 0}}
        end
      end)

    Enum.reverse(kept)
  end

  @doc "Total grapheme width of a row's runs."
  @spec row_width(row()) :: non_neg_integer()
  def row_width(runs), do: Enum.reduce(runs, 0, fn {t, _}, acc -> acc + String.length(t) end)

  @doc """
  Pad a row with trailing spaces (in `style`) out to `w` graphemes — used to extend a
  selection's background across the full column width.
  """
  @spec pad(row(), non_neg_integer(), style()) :: row()
  def pad(runs, w, style) do
    gap = w - row_width(runs)
    if gap > 0, do: runs ++ [{String.duplicate(" ", gap), style}], else: runs
  end
end
