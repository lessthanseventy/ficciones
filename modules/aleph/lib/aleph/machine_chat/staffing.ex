defmodule Aleph.MachineChat.Staffing do
  @moduledoc """
  Pure pick logic for who gets staffed as a new chat thread's lead. Pulled out of `Loop` (which
  grabs the TTY and is deliberately not unit-tested) so the picking RULE — an explicit @-mention
  wins, else the operator's configured default — has its own seam to test.
  """

  alias Aleph.Mention

  @doc """
  The coworker to staff on a new thread: the first @-mentioned coworker (resolved against
  `roster`, see `Aleph.Mention.coworkers/1`), else the default.
  """
  @spec pick_coworker(String.t(), String.t() | nil, [map()]) :: String.t() | nil
  def pick_coworker(text, default, roster \\ []) do
    case Mention.mentions(text, roster) do
      [{handle, _window} | _] -> handle
      [] -> default
    end
  end

  @doc """
  The roster-derived default lead for a thread with no explicit @-mention: the roster's
  builder-archetype entry, else its first entry, as a `<name>-machine` handle — or `nil` for an
  empty roster. Deliberately never invents a stand-in handle: a guessed `-machine` that was never
  registered as a funes agent gives `Funes.assign_lead/2` nothing to bind, and the thread ends up
  leaderless with nobody listening (the machine-chat silence bug).
  """
  @spec default_coworker([map()]) :: String.t() | nil
  def default_coworker(roster), do: builder_handle(roster) || lead_handle(roster)

  # The roster's builder-archetype handle, or nil (a builder-less, e.g. surveyor-only, cast).
  defp builder_handle(roster) do
    case Enum.find(roster, &(archetype_of(&1) in ["builder", :builder])) do
      nil -> nil
      entry -> handle(entry)
    end
  end

  defp lead_handle([entry | _]), do: handle(entry)
  defp lead_handle(_), do: nil

  # The funes handle convention: profile name + "-machine". Tolerates string (JSON) or atom keys.
  defp handle(entry), do: "#{entry["name"] || entry[:name]}-machine"
  defp archetype_of(entry), do: entry["archetype"] || entry[:archetype]
end
