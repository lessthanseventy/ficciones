defmodule Mix.Tasks.Aleph.MachineChat do
  @shortdoc "The Tlön machine-chat tab — machine threads as foldable, interactive blocks (a tmux tab)"
  @moduledoc """
  The interactive Tlön machine-chat — "Chorus for the Tlön space": the machine-scope threads
  (`Funes.Channel.machine_threads/1`) rendered as **foldable blocks** with author-turn grouping
  inside each, plus `z`-zoom to full-pane. aleph opens this as the `chat` window (a tmux tab in the
  Tlön strip, next to `pi`/`claude`); run it by hand from `modules/aleph` for the same view anywhere.

  Keys: `↑↓`/`jk` move the selected block · `Enter`/`Space` fold↔unfold · `z` zoom · `Esc` back ·
  `PgUp`/`PgDn` scroll · `q` quit.

  ## Why it POLLS the db

  A SEPARATE OS process from the cockpit, so `Funes.Bus` (node-local `Phoenix.PubSub`) is out of
  reach; it reads the one thing the two share — the SQLite file at `FUNES_DB`, carried into the Tlön
  tmux session env — polling for new messages. Reader role: no MCP, no switchboard, so it never
  binds :4041 (the cockpit already does) and Ecto's per-query logs are silenced.
  """
  use Mix.Task
  use Boundary, classify_to: Aleph

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # READER role: no MCP, no switchboard. Override before the app starts so `Funes.Application`
    # reads the false and never binds :4041.
    Application.put_env(:funes, :start_mcp, false)
    Application.put_env(:funes, :start_switchboard, false)

    # A human-facing TUI, not a service log: silence Ecto's per-query lines and funes boot chatter.
    Application.put_env(:funes, Funes.Repo, Keyword.put(Application.get_env(:funes, Funes.Repo, []), :log, false))
    Logger.configure(level: :warning)

    case Application.ensure_all_started(:funes) do
      {:ok, _apps} ->
        Aleph.MachineChat.Loop.run()

      {:error, reason} ->
        Mix.shell().error("aleph.machine_chat could not boot funes: #{inspect(reason)}")
    end
  end
end
