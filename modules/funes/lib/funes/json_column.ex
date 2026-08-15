defmodule Funes.JSONColumn do
  @moduledoc """
  An Ecto type for a JSON column: a map in Elixir, a JSON string in SQLite TEXT,
  encoded with the stdlib `JSON` module (the same one `Funes.Doctor` exports with).
  Used for `event.detail` — "a JSON detail only for what a human reads" (§4): it is
  never queried, and in `sqlite3` at 2am it reads as plain JSON text.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(map) when is_map(map), do: {:ok, map}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(json) when is_binary(json), do: {:ok, JSON.decode!(json)}

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(map) when is_map(map), do: {:ok, JSON.encode!(map)}
  def dump(_), do: :error
end
