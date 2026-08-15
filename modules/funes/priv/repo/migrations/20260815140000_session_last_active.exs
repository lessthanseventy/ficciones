defmodule Funes.Repo.Migrations.SessionLastActive do
  use Ecto.Migration

  # 012 session.last_active_at (aleph §3b, the warmth window). Presence's concrete
  # half: a session is *warm* — cheap to resume — only while its context is still in
  # the prompt cache (~1h). Past that it is COLD and must not be woken, or a poke
  # pays a full transcript re-ingestion (the "resumed a thread and burned my whole
  # allotment" footgun). Warmth is time since the session last ran a turn, so we
  # stamp `last_active_at` and the switchboard bumps it as the session acts.
  #
  # Backfill existing rows to their `started_at` (a fresh session is warm).
  def change do
    execute(
      "ALTER TABLE session ADD COLUMN last_active_at TEXT",
      "ALTER TABLE session DROP COLUMN last_active_at"
    )

    execute(
      "UPDATE session SET last_active_at = started_at WHERE last_active_at IS NULL",
      ""
    )

    create index(:session, [:last_active_at])
  end
end
