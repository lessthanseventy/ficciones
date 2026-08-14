defmodule Funes.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The test harness owns the repo lifecycle (a fresh, migrated DB per run), so
    # the app does not start it under :test.
    children =
      if Application.get_env(:funes, :start_repo, true), do: [Funes.Repo], else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: Funes.Supervisor)
  end
end
