defmodule Funes.Repo do
  use Ecto.Repo,
    otp_app: :funes,
    adapter: Ecto.Adapters.SQLite3
end
