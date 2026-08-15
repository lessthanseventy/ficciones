defmodule Funes.Switchboard.Server do
  @moduledoc """
  The switchboard as a supervised process (aleph §6): subscribes to the bus and
  wakes recipients as messages are posted. Its liveness never makes a message
  *exist* (§10) — on start it `drain/0`s the DB, so anything posted while it was
  down is still delivered; while up, it reacts to PubSub for low latency.

  Opt-in (`config :funes, :start_switchboard, true`) and off by default: it should
  not auto-poke real panes until presence-gating exists (see `Funes.Switchboard`).

  Follow-up, to land alongside a real arbiter: wakes actuate synchronously in this
  process, so a slow shell-out backend would stall every thread's delivery behind
  one poke — actuate each wake in a supervised `Task` when the backend can block.
  """
  use GenServer
  require Logger
  alias Funes.{Bus, Doctor, Switchboard}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # Subscribe synchronously so no live message is missed, but defer the (blocking)
    # drain out of init so it never stalls the supervisor's boot.
    Bus.subscribe()
    {:ok, %{}, {:continue, :drain}}
  end

  @impl true
  def handle_continue(:drain, state) do
    # Durability: deliver whatever piled up while we were gone (§10) — but degrade
    # honestly (§8) if the schema is behind, or the message table may not exist and
    # we would crash-loop the supervisor.
    case Doctor.pending() do
      [] -> Switchboard.drain()
      pending -> Logger.warning("switchboard idle: #{length(pending)} pending migration(s)")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:message, message}, state) do
    Switchboard.deliver(message)
    {:noreply, state}
  end

  # A long-lived subscriber must not crash on a stray message (a late monitor,
  # a library info): ignore anything we do not handle.
  def handle_info(_msg, state), do: {:noreply, state}
end
