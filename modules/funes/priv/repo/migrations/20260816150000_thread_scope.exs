defmodule Funes.Repo.Migrations.ThreadScope do
  use Ecto.Migration

  # 019 thread.scope (aleph Tlön isolation, 2026-08-16). A thread belongs to either a
  # PROJECT surface or the META/machine surface — the Tlön machine coworker's thread must
  # not clutter the Comms chorus or the Sessions thread list. `scope` is a CLOSED two-value
  # set guarded by a database CHECK, the `state` / `event.kind` precedent (§4: a closed set
  # lives in the DB, widening it is a migration, which is the point). The default `'project'`
  # fills existing rows; the project surfaces read `scope = 'project'` only.
  #
  # Plain SQL: SQLite's ALTER TABLE ADD COLUMN accepts NOT NULL with a DEFAULT (the default
  # fills existing rows) and a column-level CHECK whose default satisfies it. The down path
  # drops the column (SQLite 3.35+).
  def change do
    execute(
      "ALTER TABLE thread ADD COLUMN scope TEXT NOT NULL DEFAULT 'project' CHECK (scope IN ('project', 'machine'))",
      "ALTER TABLE thread DROP COLUMN scope"
    )

    create index(:thread, [:scope])
  end
end