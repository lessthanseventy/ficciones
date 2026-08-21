defmodule Aleph.Panel.Chorus do
  @moduledoc """
  ORBIS — the **chorus**: every voice (agents + the operator) heard together in one feed (design:
  "slack for agents", the default space). Unlike `Conversation` (one thread's CHAT), this is a
  single rolling timeline across ALL threads: recent messages
  (`Funes.Channel.recent_across/1`), grouped into blocks by thread so each block reads as its own
  little channel, newest at the bottom like a chat log. A reply carries a `↳` so a threaded answer
  is visually distinct from a top-level post.

  Data is `%{blocks: [%{thread: %Funes.Thread{}, messages: [%Message{}]}], focused_id: id}` — one
  block per OPEN thread (from `Funes.Channel.chorus/1`), most-recent-activity FIRST, so the feed
  and the ↑/↓ navigator share ONE order: down moves the highlight down the feed. EVERY open thread
  has a block — a fresh one with no messages shows a placeholder, so a thread you can focus is
  always visible. The focused thread's header is highlighted; a reply carries a `↳`. Read-only for
  now — composing/replying/collapsing from here is the next slice.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  # The cockpit already subscribes to ALL message events (Bus.subscribe_activity, a superset of
  # messages_topic), so the feed repaints on any thread's activity — no per-thread topic needed.
  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{blocks: blocks} = data, rect) do
    focused = data[:focused_id]
    header = [line("ORBIS · all threads", :header), blank()]

    body =
      case blocks do
        [] -> [line("no threads yet — press n", :dim)]
        bs -> Enum.flat_map(bs, &block_rows(&1, focused, rect.w))
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click any row inside a thread's block → focus that thread. The feed is header (0) + blank (1)
  # then blocks; each block's height is its rendered row count (header + wrapped messages + blank),
  # read from the SAME `block_rows/3` render uses so pick can't drift from what's painted. Scrolled:
  # add the offset so the row under the cursor maps to the right content block.
  @impl Aleph.Panel
  def pick(%{blocks: blocks} = data, rect, local_y) do
    find_block(blocks, data[:focused_id], rect.w, Aleph.Panel.scroll_offset(data) + local_y - 2)
  end

  defp find_block(_blocks, _focused, _w, idx) when idx < 0, do: nil
  defp find_block([], _focused, _w, _idx), do: nil

  defp find_block([block | rest], focused, w, idx),
    do: within_block(length(block_rows(block, focused, w)), idx, block, rest, focused, w)

  # idx falls inside this block's height → it's the clicked block; focus its thread.
  defp within_block(h, idx, %{thread: thread}, _rest, _focused, _w) when idx < h, do: {:focus_thread, thread.id}

  # past this block → subtract its height and continue down the feed.
  defp within_block(h, idx, _block, rest, focused, w), do: find_block(rest, focused, w, idx - h)

  defp block_rows(%{thread: thread, messages: messages}, focused, w) do
    style = if thread.id == focused, do: :selected, else: :header
    head = [{"▸ ", :accent}, {thread.title || "untitled", style}]

    msg_rows =
      case messages do
        [] -> [line("  no messages yet", :dim)]
        ms -> Enum.flat_map(ms, &message_rows(&1, w))
      end

    [head | msg_rows] ++ [blank()]
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
