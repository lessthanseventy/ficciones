# A fresh, migrated test database per run. The application does not start the
# repo under :test (config/test.exs), so the harness owns its lifecycle.
config = Funes.Repo.config()
File.mkdir_p!(Path.dirname(config[:database]))

_ = Ecto.Adapters.SQLite3.storage_down(config)
:ok = Ecto.Adapters.SQLite3.storage_up(config)

{:ok, _} = Funes.Repo.start_link()
Ecto.Migrator.run(Funes.Repo, :up, all: true)

ExUnit.start()
