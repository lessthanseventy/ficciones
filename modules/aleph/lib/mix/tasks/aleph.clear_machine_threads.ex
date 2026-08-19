defmodule Mix.Tasks.Aleph.ClearMachineThreads do
  @shortdoc "Clean-slate: delete every MACHINE-scope thread + its messages from the dev db"
  @moduledoc """
  B1.4's clean-slate step (design doc: `2026-08-19-aleph-B1-chat-staffs-and-spawns.md`). The old
  machine threads under the staffing experiment are disposable — clear them ONCE, by hand, before
  `ensure_thread_sessions` starts spawning per-thread windows against `Funes.staffed_machine_threads/0`,
  so the only pre-existing machine thread the cockpit finds afterward is the standing pi/claude
  coworker's (opened fresh on the next `aleph:run`).

  Boots funes as a READER (no MCP, no switchboard — this is a one-shot script, not a live
  service), against `FUNES_DB`, then deletes every `scope == "machine"` thread and its messages via
  `Funes.Channel.clear_machine_threads/0`. Project-scope threads are never touched. Prints how
  many threads/messages it cleared.
  """
  use Mix.Task
  use Boundary, classify_to: Aleph

  alias Funes.Channel

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # READER role: no MCP, no switchboard — a one-shot script never wants to bind :4041.
    Application.put_env(:funes, :start_mcp, false)
    Application.put_env(:funes, :start_switchboard, false)

    case Application.ensure_all_started(:funes) do
      {:ok, _apps} ->
        {:ok, %{threads: threads, messages: messages}} = Channel.clear_machine_threads()

        Mix.shell().info("aleph:clear-machine-threads — cleared #{threads} machine thread(s), #{messages} message(s).")

      {:error, reason} ->
        Mix.shell().error("aleph:clear-machine-threads could not boot funes: #{inspect(reason)}")
    end
  end
end
