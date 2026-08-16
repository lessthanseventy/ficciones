defmodule Aleph.Panel.ThreadList do
  @moduledoc """
  THREADS — the open threads you can focus. A thin view over `Funes.Channel.open_threads/0`;
  re-renders on the threads topic. The **selected** thread is the cockpit's one piece of shared
  state (design §8): its row is highlighted, and the right column's Dossier follows it.

  Data is `%{threads: [%Funes.Thread{}], selected_id: id | nil}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0, pad: 3]
  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.threads_topic()]

  @impl Aleph.Panel
  def render(%{threads: threads, selected_id: selected_id}, rect) do
    header = [line("THREADS", :header), blank()]

    body =
      case threads do
        [] -> [line("no open threads", :dim)]
        ts -> Enum.map(ts, &row(&1, &1.id == selected_id, rect.w))
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # The selected row gets a caret and a highlight bar padded across the column; others a dim dot.
  defp row(thread, true, w) do
    pad([{"▸ ", :selected_accent}, {thread.title, :selected_accent}], w, :selected)
  end

  defp row(thread, false, _w) do
    [{"· ", :dim}, {thread.title, :normal}]
  end
end
