defmodule Aleph.Panel.Roster do
  @moduledoc """
  IN FLIGHT — the live roster: which agents are working which threads, and whether
  they are warm. A thin view over `Funes.Staff.roster/0`; re-renders on the sessions
  topic. Each row is `%{agent, thread_id, thread_title, workspace_ref, warm?}`
  (the `workspace_ref` field is slated to become `pane_ref` — design §7).
  """
  @behaviour Aleph.Panel

  alias Funes.Bus

  @impl Aleph.Panel
  def topics(_assigns), do: [Bus.sessions_topic()]

  @impl Aleph.Panel
  def render(roster, rect) do
    roster
    |> Enum.map(&row/1)
    |> Aleph.Panel.clip(rect)
  end

  defp row(%{agent: agent, thread_title: title} = s) do
    warmth = if Map.get(s, :warm?), do: " · warm", else: ""
    "▸ #{agent} · #{title}#{warmth}"
  end
end
