import Config

# Resolve funes' SQLite path the SAME way funes' own config/runtime.exs does, so the cockpit
# and the human's `mise run funes:*` tasks read and write ONE file. Precedence:
#   1. FUNES_DB (aleph's mise tasks export the repo-local .dev DB here)
#   2. $XDG_DATA_HOME/funes/wb.db, else ~/.local/share/funes/wb.db
# Skipped under :test (aleph tests keep funes' Repo down — see config/test.exs).
if config_env() != :test do
  database =
    System.get_env("FUNES_DB") ||
      Path.join([
        System.get_env("XDG_DATA_HOME") ||
          Path.join(System.get_env("HOME") || ".", ".local/share"),
        "funes",
        "wb.db"
      ])

  File.mkdir_p!(Path.dirname(database))
  config :funes, Funes.Repo, database: database
  config :funes, maintain: System.get_env("FUNES_MAINTAIN") in ~w(1 true yes)

  # Mirror funes' own runtime flags: a dependency's config/*.exs is NOT evaluated when aleph
  # is the root app, so without these the memory pass / maintain monitor / workline root are
  # silently unreachable for aleph-embedded funes (the 4041 node).
  config :funes, memory_pass: System.get_env("FUNES_MEMORY_PASS") in ~w(1 true yes)

  if workline_root = System.get_env("FUNES_WORKLINE_ROOT") do
    config :funes, workline_root: workline_root
  end
end
