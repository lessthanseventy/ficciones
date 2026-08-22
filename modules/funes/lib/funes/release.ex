defmodule Funes.Release do
  @moduledoc """
  Release-time tasks — the operations a `mix release` needs but `mix` isn't there
  to perform. The always-up service (a self-contained release, no toolchain on
  PATH) boots by first running `bin/funes eval 'Funes.Release.migrate()'`, so an
  empty or behind schema is brought fully up before the channel serves. SQLite is
  the truth; nothing ships that cannot be repaired at 2am, and migration is the
  first repair — so it lives here, in the app, not in a shell step that could drift.
  """
  @app :funes

  @doc """
  Apply every pending migration for each configured repo, up to the latest.
  Runs against the repo's own priv migrations (bundled into the release). Returns
  `:ok`. Idempotent — an up-to-date schema runs nothing.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Roll `repo` back to migration `version` — the deliberate 2am reverse gear. Named
  repo + explicit version, never "roll back one blindly": a repair is a decision.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  @doc """
  Find-or-create the seed Tlön world row (worlds/orbis Slice 1) — the composition
  aleph's picker/survey/spawn opens on. Idempotent: a row already named "Tlön" is
  left untouched, so the flake's ExecStartPre can run it on every boot. Mirrors
  `migrate/0`'s release shape (load the app, start only what the work needs, do it),
  but `Funes.Worlds.register/1` announces on `Funes.Bus`, so PubSub must be up too —
  hence Repo + PubSub, not the full tree (no MCP/switchboard for a one-shot seed).

  `bin/funes eval` only *loads* apps, it never starts them, so the dep applications
  that own the registries these children need are missing: phoenix_pubsub starts the
  `:pg` scope named `Phoenix.PubSub` that the PG2 adapter joins, and ecto starts
  `Ecto.Repo.Registry` that the repo associates into. Start those apps first, then the
  two children under our own one-shot supervisor — otherwise the boot crashes on a
  `:pg.join`/`Ecto.Repo.Registry` call with no process.
  """
  @spec seed_world() ::
          {:ok, Funes.World.t()} | {:error, Ecto.Changeset.t()} | Funes.World.t()
  def seed_world do
    load_app()
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    {:ok, sup} =
      Supervisor.start_link(
        [{Phoenix.PubSub, name: Funes.PubSub}, Funes.Repo],
        strategy: :one_for_one
      )

    try do
      do_seed_world()
    after
      Supervisor.stop(sup)
    end
  end

  @doc """
  The seed's DB work, split out so the suite drives it against the already-running
  test repo without a release double-boot. Returns the existing Tlön (a `%World{}`)
  or the `register/1` result (`{:ok, world}` / `{:error, changeset}`).
  """
  @spec do_seed_world() ::
          {:ok, Funes.World.t()} | {:error, Ecto.Changeset.t()} | Funes.World.t()
  def do_seed_world do
    Funes.Worlds.by_name("Tlön") ||
      Funes.Worlds.register(%{
        name: "Tlön",
        type: "code",
        scope: "machine",
        paths: ["modules/*"],
        roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
      })
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Load (not start) the app so its config — including :ecto_repos and the repo's
  # database path from runtime.exs — is available without booting the supervision
  # tree. `with_repo` starts just the repo it needs and stops it after.
  defp load_app, do: Application.load(@app)
end
