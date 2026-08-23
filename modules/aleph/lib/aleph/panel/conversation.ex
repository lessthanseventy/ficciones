defmodule Aleph.Panel.Conversation do
  @moduledoc """
  CHAT — the slack-style conversation on a thread (the coordination spine, funes `Channel`).
  This is not a tmux session: agents and the human posting to a thread *is* the chat, already
  durable in funes. Serves double duty — the compact left "CHATTER" box and the full-screen
  chat view (Tab) — the only difference is the rect it's handed. Re-renders on the thread topic.

  Data is `%{title: String.t() | nil, messages: [%Funes.Message{}]}`, optionally with
  `thinking`/`working` agent lists (the focused thread's presence) rendered as a trailing
  `⋯ <agent> is thinking…` indicator — thinking counts as working, so the explicit declare
  (accent) outranks the tmux-activity inference (dim).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(%{focused_id: id}) when not is_nil(id), do: [Bus.thread_topic(id)]
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{messages: messages} = data, rect) do
    header = [line(head_label(data[:title]), :header), blank()]

    body =
      case messages do
        [] ->
          [line("no messages yet", :dim)]

        ms ->
          ms
          |> Enum.map(&message_rows(&1, rect.w))
          |> Enum.reject(&(&1 == []))
          |> Enum.intersperse([blank()])
          |> Enum.concat()
      end

    Aleph.Panel.clip(header ++ body ++ presence_rows(data), rect)
  end

  defp presence_rows(data) do
    rows =
      Enum.map(data[:thinking] || [], &line("⋯ #{&1} is thinking…", :accent)) ++
        Enum.map(data[:working] || [], &line("⋯ #{&1} is working…", :dim))

    case rows do
      [] -> []
      rows -> [blank() | rows]
    end
  end

  defp head_label(nil), do: "CHAT"
  defp head_label(title), do: "CHAT · #{title}"

  # "author: body", paragraph-aware wrap with a hanging indent so the author stays legible;
  # blank lines in the body render as paragraph breaks instead of collapsing.
  defp message_rows(%{author: author, body: body}, w) do
    prefix = "#{author}: "

    case Aleph.Text.wrap_paragraphs(prefix <> body, max(w, 1)) do
      [] -> []
      [first | rest] -> [author_run(first, author) | Enum.map(rest, &continuation/1)]
    end
  end

  defp continuation(""), do: blank()
  defp continuation(text), do: line("  " <> text, :normal)

  # Colour the author name on the first wrapped line; the rest of that line is body text.
  defp author_run(first_line, author) do
    case String.split(first_line, ": ", parts: 2) do
      [^author, tail] -> [{author, :label}, {": ", :dim}, {tail, :normal}]
      _ -> [{first_line, :normal}]
    end
  end
end
