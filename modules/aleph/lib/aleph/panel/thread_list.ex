defmodule Aleph.Panel.ThreadList do
  @moduledoc """
  THREADS — the open threads you can focus, each annotated with its live agent (the merged
  IN FLIGHT, design Addendum §A: a session is just a thread with a live agent, never a second
  list). A thin view over `Funes.Channel.open_threads/0` + `Funes.Staff.roster/0`; re-renders on
  the threads and sessions topics. The **selected** thread is the cockpit's one piece of shared
  state (design §8): its row is highlighted, and the right column's Dossier follows it.

  Data is `%{threads: [%Funes.Thread{}], selected_id: id | nil, roster: [session] | nil}` — a
  `session` is `%{thread_id, agent, warm?}`; a thread with no session shows a plain dot.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0, pad: 3]

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(%{threads: threads, selected_id: selected_id} = data, rect) do
    sessions = index_sessions(data[:roster] || [])
    header = [line("THREADS", :header), blank()]

    body =
      case threads do
        [] -> [line("no open threads", :dim)]
        ts -> Enum.map(ts, &row(&1, &1.id == selected_id, Map.get(sessions, &1.id), rect.w))
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # Click a thread row → focus it. Layout: header (0), blank (1), then one row per thread, so
  # content row 2+i is thread i. Scrolled: add the offset to land on the right content row.
  @impl Aleph.Panel
  def pick(%{threads: threads} = data, _rect, local_y) do
    threads
    |> Aleph.Panel.item_at(Aleph.Panel.scroll_offset(data) + local_y)
    |> focus_thread()
  end

  defp focus_thread(nil), do: nil
  defp focus_thread(%{id: id}), do: {:focus_thread, id}

  defp index_sessions(roster), do: Map.new(roster, &{&1.thread_id, &1})

  # The selected row gets a caret and a highlight bar padded across the column; the live agent (if
  # any) folds into the highlighted text.
  defp row(thread, true, session, w) do
    pad(
      [{"▸ ", :selected_accent}, {marker(session) <> thread.title, :selected_accent}],
      w,
      :selected
    )
  end

  # A thread with a live agent: a warmth dot (● warm / dim) + the agent (pink) + the title.
  defp row(thread, false, %{agent: agent} = session, _w) do
    dot = if Map.get(session, :warm?, false), do: {"● ", :warm}, else: {"● ", :dim}
    [dot, {agent, :accent}, {" · ", :dim}, {thread.title, :normal}]
  end

  # A thread with no live session: a plain dim dot.
  defp row(thread, false, nil, _w) do
    [{"· ", :dim}, {thread.title, :normal}]
  end

  defp marker(nil), do: ""
  defp marker(%{agent: agent}), do: "● #{agent} · "
end
