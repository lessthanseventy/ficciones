defmodule Mix.Tasks.Aleph.Run do
  @shortdoc "Launch the aleph cockpit in this terminal (run in ghostty)"
  @moduledoc """
  Boot funes (Repo + Bus) and launch the live cockpit — the workspace picker, the reactive board,
  the tmux center, chat — over the funes world at `FUNES_DB`. Runs until you quit (`q`).

  Run in a REAL terminal: `mise run aleph:run` (headless it boots funes, finds no TTY, and exits
  clean). Set up the DB first with `mise run aleph:setup`, and `mise run aleph:seed` for sample data.
  """
  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # Start aleph and its deps — funes' OTP app (PubSub always, Repo from aleph's config) comes up
    # as a dependency. A DB misconfig surfaces here rather than deep in the first read.
    case Application.ensure_all_started(:aleph) do
      {:ok, _apps} ->
        Aleph.Cockpit.run()

      {:error, reason} ->
        Mix.shell().error(
          "aleph could not boot funes: #{inspect(reason)}\n" <>
            "Did you run `mise run aleph:setup` to create + migrate the database?"
        )
    end
  end
end
