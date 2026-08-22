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
  @spec pick_coworker(String.t(), String.t(), [map()]) :: String.t()
  def pick_coworker(text, default, roster \\ []) do
    case Mention.mentions(text, roster) do
      [{handle, _window} | _] -> handle
      [] -> default
    end
  end
end
