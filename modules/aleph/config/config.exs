import Config

config :funes, Funes.Repo,
  journal_mode: :wal,
  busy_timeout: 100,
  foreign_keys: :on

# The arbiter: the switchboard actuates a wake by writing into the session's embedded ghostty
# terminal (Aleph.Arbiter), and spawns a fresh one for a cold thread the same way the `s` verb does.
# funes calls this through the behaviour seam (§8) — it never imports aleph.
config :funes, :arbiter, Aleph.Arbiter

# The crew backend (funes crew MVP): funes' spawn_crew/kill_crew tools dispatch through Funes.Crew
# to Aleph.Crew, which spawns a role's window on the tlon server IN this live node — the leader
# staffs a reviewer without booting a second BEAM. Same behaviour seam as :arbiter above.
config :funes, :crew, Aleph.Crew

# The engine-credit presence backend: the hand toggle (Funes.Presence.clock_out/1 from the
# console) — when the scarce Claude window is spent, the switchboard stops poking Claude
# sessions. A real rate-limit reader is a later local backend swapped in the same seam.
config :funes, :engine_presence, Funes.Presence.Engine.Manual

# aleph boots funes as a live dep (§6), but a dependency's own config/*.exs is NOT evaluated
# when aleph is the root app — so aleph re-declares what funes' config.exs normally provides:
# the ecto repo list and the §4 write contract (WAL + busy timeout + foreign keys). The DB
# *path* is env/runtime-resolved (config/runtime.exs); it must not be hardcoded here.
config :funes, ecto_repos: [Funes.Repo]

# A DISTINCT port from the always-up service's 4040, so the hub and the headless service
# coexist on one box (topology A: they are two funes worlds on two DBs). Both aleph's Bandit
# and its in-process `Funes.MCP.Spawn` env read `:mcp_port`, so a spawned harness is pointed
# at exactly the endpoint aleph serves. Override with FUNES_MCP_PORT in aleph's runtime if 4041
# is taken.
config :funes, mcp_port: 4041
config :funes, start_mcp: true

# aleph is the dogfood HUB (tlön topology A): it runs the full funes world in one interactive node,
# so the switchboard's wake loop and the MCP channel start here, and sessions are embedded ghostty
# terminals aleph owns (not tmux). The presence gate the wake needs (warmth AND engine-credit)
# exists; the live poke over those terminals arrives with Aleph.Arbiter.
config :funes, start_switchboard: true

# Quiet raxol_terminal's internal debug/info chatter (e.g. Buffer.Writer "Writing char"):
# at runtime it would corrupt a live TUI, and in tests it drowns the output. aleph's own
# logs stay at :warning and above.
config :logger, level: :warning

import_config "#{config_env()}.exs"
