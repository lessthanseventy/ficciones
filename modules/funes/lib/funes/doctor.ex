defmodule Funes.Doctor do
  @moduledoc """
  The 2am report. Ask the database itself whether it is sound — the arbiter's own
  answers, not our bookkeeping — and provide the JSONL escape hatch that makes it
  repairable with a text editor.
  """
  alias Funes.Repo

  @type report :: %{integrity: String.t(), tables: [String.t()], pending: non_neg_integer()}

  @spec report() :: report()
  def report do
    %{integrity: integrity_check(), tables: tables(), pending: length(pending())}
  end

  @doc "`ok`, or the first problem PRAGMA integrity_check found."
  @spec integrity_check() :: String.t()
  def integrity_check do
    %{rows: [[result]]} = Repo.query!("PRAGMA integrity_check")
    result
  end

  @doc "User tables present, sqlite internals and the migration ledger excluded."
  @spec tables() :: [String.t()]
  def tables do
    %{rows: rows} =
      Repo.query!("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'schema_migrations'
      ORDER BY name
      """)

    Enum.map(rows, fn [name] -> name end)
  end

  @doc "Migrations known but not yet applied — a non-empty list means the schema is behind."
  @spec pending() :: [{integer(), String.t()}]
  def pending do
    Repo
    |> Ecto.Migrator.migrations()
    |> Enum.filter(fn {status, _version, _name} -> status == :down end)
    |> Enum.map(fn {_status, version, name} -> {version, name} end)
  end

  @doc """
  Export one table as JSONL — the escape hatch. The table name cannot be a bound
  parameter, so it is validated against the live schema before it is interpolated:
  an unknown name is refused, not run.
  """
  @spec table_to_jsonl(String.t()) :: String.t()
  def table_to_jsonl(table) do
    unless table in tables(), do: raise(ArgumentError, "no such table: #{table}")

    %{rows: rows, columns: columns} = Repo.query!(~s|SELECT * FROM "#{table}"|)

    rows
    |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() |> JSON.encode!() end)
    |> Enum.join("\n")
  end
end
