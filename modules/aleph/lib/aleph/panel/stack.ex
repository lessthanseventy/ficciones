defmodule Aleph.Panel.Stack do
  @moduledoc """
  STACK — the machine's own changelog for the Tlön space: recent `ficciones` commits, newest first.
  Data is `%{commits: [%{hash, subject}]}` (`Aleph.Stack.commits/2`). Health (funes service, nix
  generation) is a phase-2 addition.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{commits: commits}, rect) do
    header = [line("STACK", :header), blank()]

    body =
      case commits do
        [] -> [line("no git history", :dim)]
        cs -> Enum.map(cs, &commit_row/1)
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  defp commit_row(%{hash: hash, subject: subject}), do: [{hash <> " ", :dim}, {subject, :normal}]
end
