defmodule Mix.Tasks.Aleph.Crew.Spawn do
  @shortdoc "Spawn a crew coworker (role) onto a funes task thread"
  @moduledoc """
  The leader's spawn verb. Usage:

      mix aleph.crew.spawn <role> <thread_id> --task "<what to review>"

  Boots the aleph app (funes comes up on aleph's configured port), mints the role's identity on the
  thread, spawns its `r<tid>` window on the standing `tlon` tmux server, and injects the leader's
  assignment. Run it from the leader's own shell (it already lives on that tmux server).
  """
  use Mix.Task
  use Boundary, classify_to: Aleph

  @impl true
  def run(argv) do
    case parse(argv) do
      {:ok, role, thread_id, task} ->
        Mix.Task.run("app.start")

        case Aleph.Crew.spawn(role, thread_id, task) do
          {:ok, window} -> Mix.shell().info("spawned #{role} → #{window} on thread #{thread_id}")
          {:error, reason} -> Mix.raise("crew spawn failed: #{inspect(reason)}")
        end

      {:error, msg} ->
        Mix.raise(msg)
    end
  end

  @doc false
  @spec parse([String.t()]) :: {:ok, String.t(), integer(), String.t()} | {:error, String.t()}
  def parse(argv) do
    {opts, positional, _invalid} = OptionParser.parse(argv, strict: [task: :string])

    with [role, thread_id_str] <- positional,
         {thread_id, ""} <- Integer.parse(thread_id_str),
         task when is_binary(task) <- opts[:task] do
      {:ok, role, thread_id, task}
    else
      _ -> {:error, ~s(usage: mix aleph.crew.spawn <role> <thread_id> --task "<what to review>")}
    end
  end
end
