defmodule Funes.Bootstrap do
  @moduledoc """
  Boot-time integrity (reshape slice A). Two invariants, restored on every start:
  a default workspace exists, and every thread points at a workspace that is real.
  Replaces the flake's ExecStartPre seed AND aleph's hardcoded fallback world —
  any node that boots the funes app self-heals, including the dev scratch db.

  Repair targets drift the FK pragma can't catch after the fact: table-rebuild
  migrations and pre-integrity `remove_world` both left threads pointing at dead
  world ids (observed live: a thread → world 5 with only world 1 existing).
  """
  import Ecto.Query

  alias Funes.Repo
  alias Funes.Thread
  alias Funes.World
  alias Funes.Worlds

  require Logger

  @default %{
    name: "ficciones",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "builder", "name" => "hronir"}
    ]
  }

  @doc """
  Seed-if-empty + repair. Returns `{:ok, default_world}` — the oldest world, which
  is the default home for adrift threads. Idempotent; an operator's worlds and
  any thread already housed in a live workspace are never touched.
  """
  @spec ensure() :: {:ok, World.t()} | {:error, Ecto.Changeset.t()}
  def ensure do
    with {:ok, world} <- default_world() do
      repair(world)
      {:ok, world}
    end
  end

  @doc """
  `ensure/0` for the supervision tree: any raise/exit (schema not yet migrated on
  a first boot, repo briefly down) is absorbed to `:skipped` — bootstrap must
  never take the app down with it. Every non-ok outcome is LOGGED: a broken
  bootstrap would otherwise present exactly like honest funes-down (Orbis-only
  picker) with no diagnostic anywhere.
  """
  @spec ensure_safe() :: {:ok, World.t()} | {:error, Ecto.Changeset.t()} | :skipped
  def ensure_safe do
    case ensure() do
      {:ok, _world} = ok ->
        ok

      {:error, reason} = error ->
        Logger.warning("Funes.Bootstrap: seed failed — #{inspect(reason)}; repair skipped this boot")
        error
    end
  rescue
    e ->
      Logger.warning("Funes.Bootstrap: skipped — #{Exception.message(e)}")
      :skipped
  catch
    :exit, reason ->
      Logger.warning("Funes.Bootstrap: skipped — exit #{inspect(reason)}")
      :skipped
  end

  @doc """
  Supervision-tree entry: runs `ensure_safe/0` SYNCHRONOUSLY during child startup and
  returns `:ignore` — the supervisor only proceeds to later children (consult mirror,
  MCP/Bandit) once seed + repair are done, so nothing serves against an unseeded db.
  A `{Task, fun}` child would return immediately and leave a serve-before-seed window.
  """
  def start_link do
    ensure_safe()
    :ignore
  end

  @doc false
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}
  end

  defp default_world do
    case Repo.one(from w in World, order_by: [asc: w.id], limit: 1) do
      nil -> Worlds.register(@default)
      %World{} = world -> {:ok, world}
    end
  end

  @doc """
  The default workspace's id — the oldest world, or nil when none exists yet
  (a pre-bootstrap open proceeds unhoused; the boot repair houses it). The
  open-thread paths call this so every new thread has a home from birth.
  """
  @spec default_world_id() :: integer() | nil
  def default_world_id do
    Repo.one(from w in World, order_by: [asc: w.id], limit: 1, select: w.id)
  end

  # One UPDATE: every thread whose world_id is NULL or names no live world moves
  # to the default. Runs with FKs on — the target id is real by construction.
  defp repair(%World{id: id}) do
    live = from(w in World, select: w.id)

    adrift = from(t in Thread, where: is_nil(t.world_id) or t.world_id not in subquery(live))
    Repo.update_all(adrift, set: [world_id: id])
  end
end
