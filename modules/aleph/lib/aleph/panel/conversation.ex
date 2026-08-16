defmodule Aleph.Panel.Conversation do
  @moduledoc """
  CHAT — the slack-style conversation on a thread (the coordination spine, funes `Channel`).
  This is not a tmux session: agents and the human posting to a thread *is* the chat, already
  durable in funes. Serves double duty — the compact left "CHATTER" box and the full-screen
  chat view (Tab) — the only difference is the rect it's handed. Re-renders on the thread topic.

  Data is `%{title: String.t() | nil, messages: [%Funes.Message{}]}`.
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
        [] -> [line("no messages yet", :dim)]
        ms -> Enum.flat_map(ms, &message_rows(&1, rect.w))
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  defp head_label(nil), do: "CHAT"
  defp head_label(title), do: "CHAT · #{title}"

  # "author: body", wrapped to the column with a hanging indent so the author stays legible.
  defp message_rows(%{author: author, body: body}, w) do
    prefix = "#{author}: "

    case Aleph.Text.wrap(prefix <> body, max(w, 1)) do
      [] -> []
      [first | rest] -> [author_run(first, author) | Enum.map(rest, &line("  " <> &1, :normal))]
    end
  end

  # Colour the author name on the first wrapped line; the rest of that line is body text.
  defp author_run(first_line, author) do
    case String.split(first_line, ": ", parts: 2) do
      [^author, tail] -> [{author, :label}, {": ", :dim}, {tail, :normal}]
      _ -> [{first_line, :normal}]
    end
  end
end
