defmodule Aleph.Tlon.Settings do
  @moduledoc """
  The Tlön settings modal (design: `docs/plans/2026-08-20-tlon-lazygit-panels-design.md` §Settings):
  a PURE reducer over which coworker row and which knob (model or permission) the operator has
  selected. The two principles §"Monitor vs. act" put settings here — a control you touch, not a
  readout you monitor — so it lives off the always-on panes as a key-invoked overlay.

  The reducer only navigates; it does no I/O. `target/1` hands the Cockpit the `{coworker, knob}`
  the current selection points at, and the Cockpit does the actual write (cycle the model ring via
  `Aleph.Config.put_coworker_model`, or flip yolo via `put_coworker_yolo`) — keeping this testable
  and the effect honest-scoped ("applies on next spawn").
  """

  defstruct open?: false, coworkers: [], row: 0, field: :model

  @type field :: :model | :permission
  @type intent :: :row_next | :row_prev | :field_next
  @type t :: %__MODULE__{
          open?: boolean(),
          coworkers: [String.t()],
          row: non_neg_integer(),
          field: field()
        }

  @doc "A closed modal over `coworkers` (the rows), on the first row's model knob."
  @spec new([String.t()]) :: t()
  def new(coworkers), do: %__MODULE__{coworkers: coworkers}

  @doc "Show the modal."
  @spec open(t()) :: t()
  def open(%__MODULE__{} = s), do: %{s | open?: true}

  @doc "Hide the modal (row/field selection is preserved for the next open)."
  @spec close(t()) :: t()
  def close(%__MODULE__{} = s), do: %{s | open?: false}

  @doc "The `{coworker, knob}` the current selection points at — what the Cockpit acts on."
  @spec target(t()) :: {String.t(), field()}
  def target(%__MODULE__{coworkers: cw, row: r, field: f}), do: {Enum.at(cw, r), f}

  @doc """
  The permission-toggle decision for a coworker's `permissions` map: `{:ok, next_yolo, label}` to
  flip yolo (a missing `yoloMode` reads as `ask`, so this is total — never `not nil`), or `:no_policy`
  when the profile carries no permission map to toggle.
  """
  @spec next_yolo(map() | nil) :: {:ok, boolean(), String.t()} | :no_policy
  def next_yolo(perms) when is_map(perms) do
    next = perms["yoloMode"] != true
    {:ok, next, if(next, do: "yolo (auto-approve)", else: "ask")}
  end

  def next_yolo(_), do: :no_policy

  @doc "Advance the selection by an intent. Row moves wrap the coworker list; field toggles the knob."
  @spec handle(t(), intent()) :: t()
  def handle(%__MODULE__{} = s, :row_next), do: move_row(s, +1)
  def handle(%__MODULE__{} = s, :row_prev), do: move_row(s, -1)
  def handle(%__MODULE__{field: :model} = s, :field_next), do: %{s | field: :permission}
  def handle(%__MODULE__{field: :permission} = s, :field_next), do: %{s | field: :model}
  def handle(%__MODULE__{} = s, _unknown), do: s

  # Wrap within the coworker list (a carousel — it's a short, cyclic set). An empty list stays put.
  defp move_row(%__MODULE__{coworkers: []} = s, _delta), do: s

  defp move_row(%__MODULE__{coworkers: cw, row: r} = s, delta), do: %{s | row: Integer.mod(r + delta, length(cw))}
end
