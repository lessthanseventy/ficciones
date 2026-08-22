defmodule Aleph.CockpitWorldsTest do
  @moduledoc """
  D2.3: `Aleph.Cockpit.register_world!/3` — the author face's `n` verb's funes write. Exercises
  the REAL `Funes.Worlds` write pipe (register) through the cockpit's public, pure-ish wrapper
  (like `cycle_pane_view/2`/`attach_leaf/2`), mirroring `Aleph.WorldsTest`'s temp-DB setup —
  aleph's `config/test.exs` keeps funes' Repo down, so this suite boots it itself. One of the few
  aleph suites touching the DB → `async: false`. `remove_world!/2` (D2.5) joins next commit.
  """
  use ExUnit.Case, async: false

  alias Aleph.Cockpit
  alias Ecto.Adapters.SQLite3
  alias Funes.Repo
  alias Funes.World
  alias Funes.Worlds

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_cockpit_worlds_test_#{System.unique_integer([:positive])}.db")
    Application.put_env(:funes, Repo, Keyword.merge(Application.get_env(:funes, Repo, []), database: db, pool_size: 1))

    config = Repo.config()
    _ = SQLite3.storage_down(config)
    :ok = SQLite3.storage_up(config)
    {:ok, _repo} = Repo.start_link()
    Ecto.Migrator.run(Repo, :up, all: true)

    on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = SQLite3.storage_down(config)
    end)

    :ok
  end

  setup do
    # A clean world table per test — this suite writes rows (mirrors Aleph.WorldsTest).
    Repo.delete_all(World)
    :ok
  end

  defp state(overrides), do: Map.merge(%{active_key: :orbis, author_cursor: 0, flash: nil, input: nil}, overrides)

  describe "register_world!/3 — the author face's `n` verb (D2.3)" do
    test "a valid template + name registers a world, clears the input, and flashes success" do
      s = state(%{input: %{kind: :new_world, buffer: "Ficciones2", cursor: 10, template: :code}})
      next = Cockpit.register_world!(s, :code, "Ficciones2")

      assert next.input == nil
      assert next.flash =~ "created Ficciones2"
      assert [%{name: "Ficciones2", type: "code"}] = Worlds.all()
    end

    test "the end-to-end release-bar chain: register_world! → Funes.Worlds gets a 2nd row" do
      {:ok, _tlon} = Worlds.register(%{name: "Tlön", type: "code"})
      next = Cockpit.register_world!(state(%{}), :blank, "Ficciones2")

      assert next.flash =~ "created"
      names = Worlds.all() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Ficciones2", "Tlön"]
    end

    test "a duplicate name (UNIQUE(name)) flashes an error and keeps the input open — no 2nd insert" do
      {:ok, _} = Worlds.register(%{name: "Tlön", type: "code"})
      s = state(%{input: %{kind: :new_world, buffer: "Tlön", cursor: 4, template: :code}})

      next = Cockpit.register_world!(s, :code, "Tlön")

      assert next.input == %{kind: :new_world, buffer: "Tlön", cursor: 4, template: :code}
      assert next.flash =~ "couldn't create"
      assert length(Worlds.all()) == 1
    end

    test "a blank name flashes and keeps the input open (the funes required-name changeset)" do
      s = state(%{input: %{kind: :new_world, buffer: "", cursor: 0, template: :blank}})
      next = Cockpit.register_world!(s, :blank, "")

      assert next.input.kind == :new_world
      assert next.flash =~ "couldn't create"
      assert Worlds.all() == []
    end
  end
end
