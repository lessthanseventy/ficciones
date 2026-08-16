defmodule Aleph.Panel.Chorus do
  @moduledoc """
  COMMS — the **chorus**: every voice (agents + the operator) heard together in one feed (design:
  "slack for agents", the default space). Unlike `Conversation` (one thread's CHAT), this is a
  single rolling timeline across ALL threads: recent messages
  (`Funes.Channel.recent_across/1`), grouped into blocks by thread so each block reads as its own
  little channel, newest at the bottom like a chat log. A reply carries a `↳` so a threaded answer
  is visually distinct from a top-level post.

  Data is `%{feed: [%{thread_title, thread_id, author, body, reply_to, ...}], focused_id: id}` in
  chat order. The focused thread's block is highlighted, so ↑/↓ navigation stays visible once the
  left ThreadList is gone (the rollup IS the navigator). Read-only for now — composing/replying/
  collapsing from here is the next slice; the value first is *seeing all the chatter in one place*
  instead of one thread at a time.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  # The cockpit already subscribes to ALL message events (Bus.subscribe_messages), so the feed
  # repaints on any thread's activity — no per-thread topic needed here.
  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{feed: feed} = data, rect) do
    focused = data[:focused_id]
    header = [line("COMMS · all threads", :header), blank()]

    body =
      case feed do
        [] -> [line("no messages yet", :dim)]
        msgs -> msgs |> group_consecutive() |> Enum.flat_map(&group_rows(&1, focused, rect.w))
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Consecutive messages on the same thread form one block, so the feed reads as channels rather
  # than a flat interleaving. `chunk_by` keeps chat order within and across blocks.
  defp group_consecutive(msgs) do
    msgs
    |> Enum.chunk_by(& &1.thread_id)
    |> Enum.map(fn [%{thread_title: title, thread_id: tid} | _] = block -> {title, tid, block} end)
  end

  defp group_rows({title, tid, msgs}, focused, w) do
    style = if tid == focused, do: :selected, else: :header
    head = [{"▸ ", :accent}, {title || "untitled", style}]
    [head | Enum.flat_map(msgs, &message_rows(&1, w))] ++ [blank()]
  end

  # "author: body", wrapped with a hanging indent; a reply is marked with a leading ↳.
  defp message_rows(%{author: author, body: body} = m, w) do
    mark = if m[:reply_to], do: "↳ ", else: ""

    case Aleph.Text.wrap(mark <> author <> ": " <> body, max(w, 1)) do
      [] -> []
      [first | rest] -> [author_run(first, mark, author) | Enum.map(rest, &line("  " <> &1, :normal))]
    end
  end

  # Colour the author on the first line; the rest is body text. The reply mark (if any) stays dim.
  defp author_run(first_line, mark, author) do
    case String.split(first_line, author <> ": ", parts: 2) do
      [lead, tail] when lead in [mark, ""] ->
        Enum.reject([{mark, :dim}, {author, :label}, {": ", :dim}, {tail, :normal}], fn {t, _} -> t == "" end)

      _ ->
        [{first_line, :normal}]
    end
  end
end
