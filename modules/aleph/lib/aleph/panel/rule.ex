defmodule Aleph.Panel.Rule do
  @moduledoc "A vertical column separator — the `│` gutter between the cockpit's regions."
  @behaviour Aleph.Panel

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(_data, %{h: h} = rect) do
    List.duplicate(Aleph.Panel.line("│", :separator), h) |> Aleph.Panel.clip(rect)
  end
end
