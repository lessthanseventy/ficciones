defmodule Menard.Application do
  @moduledoc false
  use Application

  # Nothing to supervise by default: the library is pure. `mix menard.mcp` adds the stdio server.
  @impl true
  def start(_type, _args), do: Supervisor.start_link([], strategy: :one_for_one, name: Menard.Supervisor)
end
