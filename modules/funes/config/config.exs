import Config

# The §4 write contract, applied at the adapter: WAL so one writer never blocks
# readers, a *bounded* busy_timeout so a held lock fails fast and retryably, and
# foreign keys on so references are real. The database path is set per-env.
config :funes, Funes.Repo,
  journal_mode: :wal,
  busy_timeout: 100,
  foreign_keys: :on

config :funes, ecto_repos: [Funes.Repo]

import_config "#{config_env()}.exs"
