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
    children =
      [
        {DynamicSupervisor, name: Aleph.TerminalSup, strategy: :one_for_one},
        Aleph.Sessions
      ] ++ maybe_worlds()

    Supervisor.start_link(children, strategy: :one_for_one, name: Aleph.Supervisor)
  end

  # Event-driven cache of funes' worlds so the per-render picker/survey never hit the DB. Gated
  # off under test (config/test.exs: `start_worlds: false`): the app-global would subscribe to the
  # funes worlds Bus and cache worlds registered by async DB tests, polluting Space.all/0 for the
  # pure-render tests. With it unstarted, fetch_worlds/0 degrades to [] → the deterministic Tlön
  # fallback the render tests rely on.
  defp maybe_worlds do
    if Application.get_env(:aleph, :start_worlds, true), do: [Aleph.Worlds], else: []
  end
end
