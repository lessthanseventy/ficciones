defmodule Aleph.Worlds do
  @moduledoc """
  An event-driven cache of funes' worlds (worlds/orbis Slice 1, Task B1).

  `Space.all/0` and the Orbis survey are per-render hot paths — reading
  `Funes.Worlds.all/0` there would be a funes DB hit every frame, the same
  per-frame-gather regression the survey already caught. So this GenServer loads the
  world list once, subscribes to the funes worlds Bus topic, and reloads only when a
  world is registered/edited/removed. `all/0` then serves the cached list — no DB per
  render. funes runs in-process in aleph (the cockpit already reads `Funes.Board`/
  `Funes.Channel` directly), so `Funes.Worlds`/`Funes.Bus` work like any local call.

  `all/0` is a `GenServer.call`, not a `:persistent_term` read: the caller is the single
  cockpit render process, so there is no call contention, and the win we needed was
  killing the *DB* hit (the cache does that) — the message round-trip is negligible and
  keeps the state per-instance (testable) rather than global.

  Funes-down at boot or an empty table both yield `[]`; callers (B2/B3) decide the
  hardcoded-Tlön fallback. The load is guarded so a funes hiccup can never crash aleph
  boot — a failed reload keeps the previous cache.
  """
  use GenServer

  alias Funes.Bus

  @world_events [:world_registered, :world_edited, :world_removed]
  # The aleph-shaped subset lifted off each `Funes.World` — dropping `knobs`/`created_at`.
  # Taken by key (not a struct match) so aleph needn't reference funes' unexported struct.
  @fields [:name, :type, :paths, :roster, :scope]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The cached worlds as aleph-shaped `%{name, type, paths, roster, scope}` maps."
  def all(server \\ __MODULE__), do: GenServer.call(server, :all)

  @impl true
  def init(_opts) do
    Bus.subscribe_worlds()
    {:ok, load([])}
  end

  @impl true
  def handle_call(:all, _from, worlds), do: {:reply, worlds, worlds}

  @impl true
  def handle_info({tag, _world}, worlds) when tag in @world_events do
    {:noreply, load(worlds)}
  end

  def handle_info(_msg, worlds), do: {:noreply, worlds}

  # Load + shape the world list; on any funes error keep `fallback` (init: `[]`; a
  # reload: the prior cache) so a DB blip never takes the cockpit down.
  defp load(fallback) do
    Enum.map(Funes.Worlds.all(), &shape/1)
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end

  defp shape(world), do: Map.take(world, @fields)
end
