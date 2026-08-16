defmodule Aleph.Panel.Roster do
  @moduledoc """
  IN FLIGHT — the live roster: which agents are working which threads, and whether they are
  warm (`Funes.Presence`). A thin view over `Funes.Staff.roster/0`; re-renders on the sessions
  topic. Each row is `%{agent, thread_id, thread_title, pane_ref, warm?}` (the `pane_ref`
  handle is opaque — design §5/§7).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]
  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(roster, rect) do
    header = [line("IN FLIGHT", :header), blank()]

    body =
      case roster do
        [] -> [line("no one on the clock", :dim)]
        rows -> Enum.map(rows, &row/1)
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  # ● warm / ○ cold, then the agent and the thread they're on.
  defp row(%{agent: agent, thread_title: title} = s) do
    warm? = Map.get(s, :warm?, false)
    dot = if warm?, do: {"●", :warm}, else: {"○", :dim}
    [dot, {" ", :normal}, {agent, :accent}, {" · ", :dim}, {title, :normal}]
  end
end
