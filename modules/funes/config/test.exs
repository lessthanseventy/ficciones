import Config

# In test the harness manages the repo lifecycle (fresh, migrated DB per run),
# so the application does not start it. The DB is a repo-local scratch file,
# never the real one.
config :funes, start_repo: false

config :funes, Funes.Repo,
  database: Path.expand("../.dev/funes_test.db", __DIR__),
  pool_size: 1
