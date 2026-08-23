defmodule Aleph.CockpitWorldsTest do
  @moduledoc """
  D2, Chunk 1: `Aleph.Cockpit.register_world!/3` (D2.3) and `remove_world!/2` (D2.5) — the author
  face's `n`/`d` funes writes. Exercises the REAL `Funes.Worlds` write pipe (register/remove)
  through the cockpit's public, pure-ish wrappers (like `cycle_pane_view/2`/`attach_leaf/2`),
  mirroring `Aleph.WorldsTest`'s temp-DB setup — aleph's `config/test.exs` keeps funes' Repo down,
  so this suite boots it itself. One of the few aleph suites touching the DB → `async: false`.
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

  describe "remove_world!/2 — the author face's two-key `d` confirm (D2.5)" do
    test "removes the world and flashes success" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_world!(state(%{}), w.id)

      assert next.flash =~ "deleted Freedonia"
      assert Worlds.all() == []
    end

    test "removing the ACTIVE world resolves active_key to :orbis — never stranded on a dead space" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_world!(state(%{active_key: w.id}), w.id)

      assert next.active_key == :orbis
    end

    test "removing a world that ISN'T active leaves active_key untouched" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_world!(state(%{active_key: :orbis}), w.id)

      assert next.active_key == :orbis
    end

    test "author_cursor clamps to the shrunk list" do
      {:ok, w1} = Worlds.register(%{name: "A", type: "blank"})
      {:ok, _w2} = Worlds.register(%{name: "B", type: "blank"})

      next = Cockpit.remove_world!(state(%{author_cursor: 1}), w1.id)

      assert next.author_cursor == 0
    end

    test "a missing world (already gone) flashes, never crashes" do
      next = Cockpit.remove_world!(state(%{}), 999_999)
      assert next.flash =~ "already gone"
    end
  end

  describe "edit_world!/3 — the field editor's immediate apply (D2.4 Chunk 2a)" do
    test "a valid attrs map updates the row and flashes success" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "code"})
      next = Cockpit.edit_world!(state(%{}), w.id, %{type: "life"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia", type: "life"}] = Worlds.all()
    end

    test "scope, paths, and roster all apply through the same wrapper" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      Cockpit.edit_world!(state(%{}), w.id, %{scope: "machine"})
      Cockpit.edit_world!(state(%{}), w.id, %{paths: ["a", "b"]})
      next = Cockpit.edit_world!(state(%{}), w.id, %{roster: [%{"archetype" => "assistant", "name" => "amy"}]})

      assert next.flash =~ "updated"

      assert [%{scope: "machine", paths: ["a", "b"], roster: [%{"archetype" => "assistant", "name" => "amy"}]}] =
               Worlds.all()
    end

    test "a missing world (already gone) flashes, never crashes" do
      next = Cockpit.edit_world!(state(%{}), 999_999, %{type: "life"})
      assert next.flash =~ "already gone"
    end

    test "name is immutable — edit_changeset drops it, no error, no rename" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.edit_world!(state(%{}), w.id, %{name: "Ignored"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia"}] = Worlds.all()
    end

    test "an invalid type (outside the DB CHECK's closed set) flashes, never crashes" do
      {:ok, w} = Worlds.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.edit_world!(state(%{}), w.id, %{type: "nonsense"})

      assert next.flash =~ "edit failed"
      assert [%{type: "blank"}] = Worlds.all()
    end
  end
end
