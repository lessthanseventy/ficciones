defmodule Aleph.Panel.Stack do
  @moduledoc """
  STACK — the machine's own changelog for the Tlön space: the current branch with tracking
  status, working-tree summary, recent `ficciones` commits (newest first), and git status.
  Health (services, system metrics, tools) lives in the HEALTH panel next door.

  Data is `%{branch, dirty, ahead, behind, status_summary, commits: [%{hash, subject, time, author}]}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(
        %{branch: branch, dirty: dirty, ahead: ahead, behind: behind, status_summary: summary, commits: commits},
        rect
      ) do
    header = [line("STACK", :header), blank()]
    branch_line = branch_row(branch, dirty, ahead, behind)

    status_line =
      case summary do
        nil -> []
        s when s.staged == 0 and s.unstaged == 0 and s.untracked == 0 -> []
        s -> [status_row(s)]
      end

    body =
      case commits do
        [] -> [line("no git history", :dim)]
        cs -> Enum.map(cs, &commit_row/1)
      end

    Aleph.Panel.clip(header ++ [branch_line | status_line ++ body], rect)
  end

  defp branch_row(nil, _dirty, _ahead, _behind), do: [{"  no branch", :dim}]

  defp branch_row(branch, dirty, ahead, behind) do
    tracking = tracking_suffix(ahead, behind)
    dirty_mark = if dirty, do: [{" ✗", :label}], else: []
    [{"  ", :dim}, {branch, :label}] ++ tracking ++ dirty_mark
  end

  defp tracking_suffix(nil, nil), do: []

  defp tracking_suffix(ahead, behind) do
    parts =
      []
      |> then(fn ps -> if ahead && ahead > 0, do: [{" ↑", :warm}, {Integer.to_string(ahead), :normal} | ps], else: ps end)
      |> then(fn ps ->
        if behind && behind > 0, do: [{" ↓", :label}, {Integer.to_string(behind), :normal} | ps], else: ps
      end)

    if parts == [], do: [], else: [{" ", :dim} | parts]
  end

  defp status_row(summary) do
    parts =
      []
      |> then(fn ps -> if summary.staged > 0, do: [{"+" <> Integer.to_string(summary.staged), :warm} | ps], else: ps end)
      |> then(fn ps ->
        if summary.unstaged > 0, do: [{"~" <> Integer.to_string(summary.unstaged), :normal} | ps], else: ps
      end)
      |> then(fn ps ->
        if summary.untracked > 0, do: [{"?" <> Integer.to_string(summary.untracked), :dim} | ps], else: ps
      end)

    # Join with spaces
    joined = Enum.intersperse(parts, {" ", :dim})
    [{"  ", :dim} | joined]
  end

  defp commit_row(%{hash: hash, subject: subject, time: time, author: author}) do
    short_author = short(author)
    [{hash <> " ", :dim}, {time <> " ", :dim}, {short_author <> " ", :accent}, {subject, :normal}]
  end

  defp short(nil), do: "?"
  defp short(name), do: name |> String.split() |> List.first() |> to_string()
end
