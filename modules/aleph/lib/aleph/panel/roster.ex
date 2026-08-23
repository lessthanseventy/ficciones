defmodule Aleph.Panel.Roster do
  @moduledoc """
  IN FLIGHT — the live roster: which agents are working which threads, and whether they are
  warm (`Funes.Presence`). A thin view over `Funes.Staff.roster/0`; re-renders on the sessions
  topic. Each row is `%{agent, thread_id, thread_title, pane_ref, warm?}` (the `pane_ref`
  handle is opaque — design §5/§7).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2]

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(%{sessions: roster}, rect) do
    body =
      case roster do
        [] -> [line("no one on the clock", :dim)]
        rows -> Enum.map(rows, &row/1)
      end

    Aleph.Panel.clip(body, rect)
  end

  # Click a session row → focus the thread it's working. Rows start at 0 (title now lives on the
  # frame); scrolled panels add the offset to land on content.
  @impl Aleph.Panel
  def pick(%{sessions: roster} = data, _rect, local_y) do
    roster
    |> Enum.at(Aleph.Panel.scroll_offset(data) + local_y)
    |> focus_thread()
  end

  defp focus_thread(nil), do: nil
  defp focus_thread(%{thread_id: id}), do: {:focus_thread, id}

  # ● warm / ○ cold, then the agent and the thread they're on.
  defp row(%{agent: agent, thread_title: title} = s) do
    warm? = Map.get(s, :warm?, false)
    dot = if warm?, do: {"●", :warm}, else: {"○", :dim}
    [dot, {" ", :normal}, {agent, :accent}, {" · ", :dim}, {title, :normal}]
  end
end
