defmodule Aleph.Panel do
  @moduledoc """
  A panel is a component; a view is a composition of panels; nothing is a prebaked
  full-screen template (design §3). A panel is a **thin view over a funes read model**
  and holds no logic of its own:

    - `topics/1` — the funes Bus topics whose events should re-render this panel.
    - `render/2` — turn the panel's data into lines, clipped to its rect.

  `read/1` (which funes function feeds the panel) joins this behaviour when the live
  brain is wired; until then the brain passes data in directly so the render path is
  a pure, headlessly-testable function.
  """

  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), w: pos_integer(), h: pos_integer()}

  @doc "The funes Bus topics whose events should re-render this panel."
  @callback topics(assigns :: map()) :: [String.t()]

  @doc "Render the panel's data into lines, each clipped to the rect's width and the list to its height."
  @callback render(data :: term(), rect()) :: [String.t()]

  @doc "Clip lines to a rect: at most `h` lines, each at most `w` graphemes wide."
  @spec clip([String.t()], rect()) :: [String.t()]
  def clip(lines, %{w: w, h: h}) do
    lines
    |> Enum.take(h)
    |> Enum.map(&String.slice(&1, 0, w))
  end
end
