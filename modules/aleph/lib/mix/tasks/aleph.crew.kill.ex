defmodule Mix.Tasks.Aleph.Crew.Kill do
  @shortdoc "Tear down a crew coworker's window on a funes thread"
  @moduledoc "Usage: `mix aleph.crew.kill <thread_id> [role]` (role defaults to reviewer)."
  use Mix.Task
  use Boundary, classify_to: Aleph

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    case parse(argv) do
      {:ok, role, thread_id} ->
        boot!()
        :ok = Aleph.Crew.kill(role, thread_id)
        Mix.shell().info("killed #{role} window on thread #{thread_id}")

      {:error, msg} ->
        Mix.raise(msg)
    end
  end

  # Boot aleph (which starts funes) before touching Aleph.Crew. A boot failure gets a setup hint.
  defp boot! do
    case Application.ensure_all_started(:aleph) do
      {:ok, _} -> :ok
      {:error, reason} -> Mix.raise("aleph failed to boot (#{inspect(reason)}) — try `mise run aleph:setup`")
    end
  end

  @doc false
  @spec parse([String.t()]) :: {:ok, String.t(), integer()} | {:error, String.t()}
  def parse([thread_id_str]), do: parse([thread_id_str, "reviewer"])

  def parse([thread_id_str, role]) do
    case Integer.parse(thread_id_str) do
      {thread_id, ""} -> {:ok, role, thread_id}
      _ -> {:error, "usage: mix aleph.crew.kill <thread_id> [role]"}
    end
  end

  def parse(_argv), do: {:error, "usage: mix aleph.crew.kill <thread_id> [role]"}
end
