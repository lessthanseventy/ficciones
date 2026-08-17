defmodule Aleph.Panel.Logbook do
  @moduledoc """
  LOGBOOK — the Tlön session's shared notebook: open issues and recent messages on the machine
  thread. A "mini chat window" for notes, observations, and agent findings about the env. Issues
  are not a bug tracker — they're the machine talking to itself about what it found, and the
  operator dropping thoughts mid-session. Any coworker on the env can file one.

  Data is `%{thread, issues: [%Issue{}], messages: [%Message{}]}` or `nil` when funes is down.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(nil, rect) do
    Aleph.Panel.clip([line("LOGBOOK", :header), blank(), line("no machine thread", :dim)], rect)
  end

  @impl Aleph.Panel
  def render(data, rect) do
    header = [line("LOGBOOK", :header), blank()]
    body = logbook_rows(data, rect.w)
    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a message row → focus the machine thread (so composing targets it).
  @impl Aleph.Panel
  def pick(%{thread: %{id: id}}, _rect, _local_y), do: {:focus_thread, id}
  def pick(_data, _rect, _local_y), do: nil

  defp logbook_rows(%{issues: [], messages: []}, _w) do
    [line("all clear", :dim)]
  end

  defp logbook_rows(data, w) do
    issue_rows(data.issues, w) ++
      message_rows(data.messages, w)
  end

  # -- Issues: open findings that need attention --

  defp issue_rows([], _w), do: []

  defp issue_rows(issues, w) do
    rows = Enum.flat_map(issues, &issue_rows_single(&1, w))
    [line("ISSUES", :label) | rows] ++ [blank()]
  end

  defp issue_rows_single(%{summary: summary, found_by: found_by}, w) do
    who = if found_by && found_by != "", do: found_by, else: "?"
    # Wrap just the summary text, then attach the author on the first line.
    case Aleph.Text.wrap(summary, max(w - 2, 1)) do
      [] ->
        [[{"✗ ", :label}, {"(empty issue)", :dim}]]

      [first | rest] ->
        first_row = [{"✗ ", :label}, {first, :normal}, {" · ", :dim}, {who, :accent}]
        rest_rows = Enum.map(rest, &[{"  ", :dim}, {&1, :normal}])
        [first_row | rest_rows]
    end
  end

  # -- Messages: recent activity on the machine thread --

  defp message_rows([], _w), do: []

  defp message_rows(messages, w) do
    rows = Enum.flat_map(messages, &message_rows_single(&1, w))
    [line("ACTIVITY", :label) | rows]
  end

  defp message_rows_single(%{author: author, body: body}, w) do
    mark = "▸ "

    case Aleph.Text.wrap(mark <> author <> ": " <> body, max(w, 1)) do
      [] ->
        []

      [first | rest] ->
        first_run = author_run(first, mark, author)
        rest_rows = Enum.map(rest, &[{"  ", :dim}, {&1, :normal}])
        [first_run | rest_rows]
    end
  end

  defp author_run(first_line, mark, author) do
    case String.split(first_line, author <> ": ", parts: 2) do
      [lead, tail] when lead in [mark, ""] ->
        Enum.reject([{mark, :dim}, {author, :label}, {": ", :dim}, {tail, :normal}], fn {t, _} -> t == "" end)

      _ ->
        [{first_line, :normal}]
    end
  end
end
