defmodule Mix.Tasks.Aleph.Crew.Kill do
  @shortdoc "Tear down a crew coworker's window on a funes thread"
  @moduledoc "Usage: `mix aleph.crew.kill <thread_id> [role]` (role defaults to reviewer)."
  use Mix.Task
  use Boundary, classify_to: Aleph

  @impl true
  def run(argv) do
    case parse(argv) do
      {:ok, role, thread_id} ->
        Mix.Task.run("app.start")
        :ok = Aleph.Crew.kill(role, thread_id)
        Mix.shell().info("killed #{role} window on thread #{thread_id}")

      {:error, msg} ->
        Mix.raise(msg)
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
