defmodule Aleph.Panel.Tools do
  @moduledoc """
  TOOLS — installed tool versions for the Tlön space (`Aleph.Stack.tools/0`). "What's new"
  changelogs are phase 2 (they need network); the version line is the honest v1.
  Data is `%{tools: [%{name, version}]}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{tools: tools}, rect) do
    header = [line("TOOLS", :header), blank()]
    body = Enum.map(tools, &tool_row/1)
    Aleph.Panel.clip(header ++ body, rect)
  end

  defp tool_row(%{name: name, version: version}) do
    [{String.pad_trailing(name, 8), :label}, {version, :normal}]
  end
end
