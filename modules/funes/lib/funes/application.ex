defmodule Funes.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # PubSub is always up — it is the switchboard's nudge and cheap to run, and the
    # test harness needs it so Channel.post can broadcast. The Repo is started
    # except under :test (the harness owns its lifecycle). The switchboard Server is
    # opt-in (off by default) until presence-gating exists — see Funes.Switchboard.
    children =
      [{Phoenix.PubSub, name: Funes.PubSub}] ++
        maybe(:start_repo, true, Funes.Repo) ++
        maybe(:start_switchboard, false, Funes.Switchboard.Server)

    Supervisor.start_link(children, strategy: :one_for_one, name: Funes.Supervisor)
  end

  defp maybe(key, default, child) do
    if Application.get_env(:funes, key, default), do: [child], else: []
  end
end
