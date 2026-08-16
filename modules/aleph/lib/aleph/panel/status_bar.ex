defmodule Aleph.Panel.StatusBar do
  @moduledoc """
  The bottom bar: the active workspace, the focused thread, and the key hints. One row, always
  present. Data is `%{workspace: String.t(), thread: String.t() | nil}`.
  """
  @behaviour Aleph.Panel

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{workspace: workspace, thread: thread}, rect) do
    focus = thread || "—"

    row = [
      {" ", :selected},
      {workspace, :selected_accent},
      {"  ·  ", :dim},
      {focus, :selected},
      {"  ·  ", :dim},
      {"Tab workspace   ↑↓ thread   Enter focus   q quit", :dim}
    ]

    Aleph.Panel.clip([Aleph.Panel.pad(row, rect.w, :selected)], rect)
  end
end
