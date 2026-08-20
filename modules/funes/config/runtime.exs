import Config

# The database path is resolved from the environment only — no distro-isms, no
# hardcoded home. FUNES_DB overrides; otherwise the XDG data dir, defaulting to
# ~/.local/share. Test manages its own path (config/test.exs), so skip it here.
if config_env() != :test do
  data_home =
    System.get_env("XDG_DATA_HOME") ||
      Path.join(System.get_env("HOME") || ".", ".local/share")

  database = System.get_env("FUNES_DB") || Path.join([data_home, "funes", "wb.db"])
  File.mkdir_p!(Path.dirname(database))

  config :funes, Funes.Repo, database: database
end

# The operator's handle — who the human IS on this machine's channel. Local
# configuration, never identity in the design (§8); the same default aleph uses.
# `Dossier.bank_stated_fact` trusts only this author for `stated` provenance.
config :funes, operator: System.get_env("FUNES_OPERATOR") || "andrew"

# The sovereign channel is opt-in (pi doc §2a): a node that serves agents flips it on.
# `mise run funes:serve` sets FUNES_START_MCP=1 so a hand-spawned pi pane has something to
# register with. Guarded out of :test — the suite owns its own MCP lifecycle on its own
# port, and this guard means a stray FUNES_START_MCP=1 in a dev shell can't bind Bandit
# during `mix test`. The port is loopback-only (Funes.Application); FUNES_MCP_PORT lets a
# second node avoid a clash.
if config_env() != :test do
  config :funes,
    start_mcp: System.get_env("FUNES_START_MCP") in ~w(1 true yes),
    mcp_port: String.to_integer(System.get_env("FUNES_MCP_PORT") || "4040")
end
