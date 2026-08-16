defmodule Aleph.Application do
  @moduledoc """
  aleph's OTP entrypoint. Supervises the session layer — a `DynamicSupervisor` for the embedded
  session terminals (`Aleph.Terminal`) and the `Aleph.Sessions` registry over it — so a session
  outlives a render and a crash never takes the cockpit down. The cockpit itself grabs the TTY and
  is NOT supervised here (it runs only under `mix aleph.run`).
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: Aleph.TerminalSup, strategy: :one_for_one},
      Aleph.Sessions
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Aleph.Supervisor)
  end
end
