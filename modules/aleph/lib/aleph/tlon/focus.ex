defmodule Aleph.Tlon.Focus do
  @moduledoc """
  The Tlön lazygit focus state machine (design: `docs/plans/2026-08-20-tlon-lazygit-panels-design.md`):
  a PURE reducer over where keyboard focus sits — which sidebar column, which pane down that column,
  which section within the pane, and whether we're in the center terminal (which forwards its keys to
  tmux). The Cockpit renders the focus highlight and routes `j/k`/`Enter` to the focused pane off
  this; nothing here touches the TTY.

  The 4-level nav (design §interaction model): `Ctrl+Space` toggles the terminal; `h`/`l` move a pane
  up/down a column; `H`/`L` jump between columns; `Tab` cycles sections within a pane. `j`/`k` (the
  item cursor) live with each pane's own list state, not here.

  `layout` is the shape the reducer navigates: `%{left: [pane], right: [pane], sections: %{pane => n}}`.
  """

  defstruct in_terminal?: true, column: :left, pane: 0, section: 0

  @type intent :: :toggle_terminal | :pane_next | :pane_prev | :col_left | :col_right | :section_next
  @type t :: %__MODULE__{
          in_terminal?: boolean(),
          column: :left | :right,
          pane: non_neg_integer(),
          section: non_neg_integer()
        }

  @doc "Initial focus: in the terminal, keys forwarding to tmux."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The pane key focus currently sits on, per `layout`."
  @spec focused_pane(t(), map()) :: atom() | nil
  def focused_pane(%__MODULE__{column: col, pane: i}, layout), do: Enum.at(column(layout, col), i)

  @doc "Advance the focus by an intent. A nav intent while in the terminal is a no-op (tmux owns the keys)."
  @spec handle(t(), map(), intent()) :: t()
  def handle(%__MODULE__{} = s, _layout, :toggle_terminal), do: %{s | in_terminal?: not s.in_terminal?}
  def handle(%__MODULE__{in_terminal?: true} = s, _layout, _intent), do: s

  def handle(%__MODULE__{} = s, layout, :pane_next), do: move_pane(s, layout, +1)
  def handle(%__MODULE__{} = s, layout, :pane_prev), do: move_pane(s, layout, -1)
  def handle(%__MODULE__{} = s, layout, :col_right), do: switch_column(s, layout, :right)
  def handle(%__MODULE__{} = s, layout, :col_left), do: switch_column(s, layout, :left)

  def handle(%__MODULE__{} = s, layout, :section_next) do
    %{s | section: rem(s.section + 1, section_count(s, layout))}
  end

  def handle(%__MODULE__{} = s, _layout, _unknown), do: s

  # Clamp within the current column (no wrap — h/l is vertical movement, not a carousel); a pane
  # change clears the section.
  defp move_pane(s, layout, delta) do
    max_i = length(column(layout, s.column)) - 1
    pane = min(max(s.pane + delta, 0), max_i)
    %{s | pane: pane, section: if(pane == s.pane, do: s.section, else: 0)}
  end

  # Jump columns, clamping the pane index into the target column's bounds; section clears.
  defp switch_column(s, layout, col) do
    max_i = max(length(column(layout, col)) - 1, 0)
    %{s | column: col, pane: min(s.pane, max_i), section: 0}
  end

  defp section_count(s, layout) do
    max(Map.get(layout[:sections] || %{}, focused_pane(s, layout), 1), 1)
  end

  defp column(layout, :left), do: layout[:left] || []
  defp column(layout, :right), do: layout[:right] || []
end
