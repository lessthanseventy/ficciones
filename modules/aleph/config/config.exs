import Config

# Quiet raxol_terminal's internal debug/info chatter (e.g. Buffer.Writer "Writing char"):
# at runtime it would corrupt a live TUI, and in tests it drowns the output. aleph's own
# logs stay at :warning and above.
config :logger, level: :warning

# aleph boots funes as a live dep (§6), but a dependency's own config/*.exs is NOT evaluated
# when aleph is the root app — so aleph re-declares what funes' config.exs normally provides:
# the ecto repo list and the §4 write contract (WAL + busy timeout + foreign keys). The DB
# *path* is env/runtime-resolved (config/runtime.exs); it must not be hardcoded here.
config :funes, ecto_repos: [Funes.Repo]

config :funes, Funes.Repo,
  journal_mode: :wal,
  busy_timeout: 100,
  foreign_keys: :on

# The cockpit needs the Bus (PubSub, always on) and the Repo (reads), but never the
# switchboard's auto-wake loop — that stays Inert until the presence gate exists (design §5).
config :funes, start_switchboard: false

import_config "#{config_env()}.exs"
