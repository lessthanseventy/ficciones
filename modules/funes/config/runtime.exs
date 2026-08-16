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
