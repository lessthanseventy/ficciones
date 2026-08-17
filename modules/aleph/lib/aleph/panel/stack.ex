defmodule Aleph.Panel.Stack do
  @moduledoc """
  STACK — the machine's own changelog for the Tlön space: the current branch, recent
  `ficciones` commits with relative time and author (newest first), and git working-tree
  status. Health (funes service, nix generation) lives in the HEALTH panel next door.

  Data is `%{branch, dirty, commits: [%{hash, subject, time, author}]}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{branch: branch, dirty: dirty, commits: commits}, rect) do
    header = [line("STACK", :header), blank()]
    branch_line = branch_row(branch, dirty)

    body =
      case commits do
        [] -> [line("no git history", :dim)]
        cs -> Enum.map(cs, &commit_row/1)
      end

    Aleph.Panel.clip(header ++ [branch_line | body], rect)
  end

  defp branch_row(nil, _dirty), do: [{"  no branch", :dim}]
  defp branch_row(branch, true), do: [{"  ", :dim}, {branch, :label}, {" ✗", :label}]
  defp branch_row(branch, false), do: [{"  ", :dim}, {branch, :label}]

  defp commit_row(%{hash: hash, subject: subject, time: time, author: author}) do
    short_author = short(author)
    [{hash <> " ", :dim}, {time <> " ", :dim}, {short_author <> " ", :accent}, {subject, :normal}]
  end

  defp short(nil), do: "?"
  defp short(name), do: name |> String.split() |> List.first() |> to_string()
end
