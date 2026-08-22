defmodule Aleph.WorldsDownTest do
  @moduledoc """
  The funes-down guard (Task B1), isolated from the DB suite below: aleph's test env
  keeps funes' Repo DOWN (config/test.exs `start_repo: false`), so `Funes.Worlds.all/0`
  raises here. `Aleph.Worlds` must swallow that at init and serve `[]` — proving a funes
  hiccup can never crash aleph boot. No Repo is started, so nothing to tear down.
  """
  use ExUnit.Case, async: false

  test "funes down at init is swallowed → [] (aleph boot never crashes)" do
    name = :"worlds_down_#{System.unique_integer([:positive])}"
    {:ok, pid} = Aleph.Worlds.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Aleph.Worlds.all(pid) == []
  end
end

defmodule Aleph.WorldsTest do
  @moduledoc """
  The `Aleph.Worlds` cache (worlds/orbis Slice 1, Task B1): an event-driven read of
  funes' `world` table, so the per-render hot paths (`Space.all/0`, the survey) hit a
  cached list instead of the DB every frame. funes runs in-process in aleph, so we drive
  the real `Funes.Worlds`/`Funes.Bus` — but aleph's test env keeps funes' Repo DOWN
  (config/test.exs `start_repo: false`), so this suite boots the Repo itself, mirroring
  funes' own test_helper. It is the only aleph suite that touches the DB → `async: false`.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQLite3
  alias Funes.Repo
  alias Funes.World
  alias Funes.Worlds

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_worlds_test_#{System.unique_integer([:positive])}.db")
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
    # A clean world table per test — this is the only suite writing rows.
    Repo.delete_all(World)
    :ok
  end

  # An isolated cache instance (the app already supervises one under the module name).
  defp start_worlds do
    name = :"worlds_#{System.unique_integer([:positive])}"
    {:ok, pid} = Aleph.Worlds.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  test "all/0 returns the worlds present at boot, aleph-shaped" do
    {:ok, _} =
      Worlds.register(%{
        name: "Tlön",
        type: "code",
        scope: "machine",
        paths: ["modules/*"],
        roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
      })

    pid = start_worlds()

    assert [world] = Aleph.Worlds.all(pid)

    assert world == %{
             name: "Tlön",
             type: "code",
             scope: "machine",
             paths: ["modules/*"],
             roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
           }
  end

  test "a :world_registered Bus event refreshes the cache" do
    pid = start_worlds()
    assert Aleph.Worlds.all(pid) == []

    # register/1 announces on the worlds topic; the cache is subscribed and reloads.
    # FIFO mailbox: the broadcast lands before the following all/0 call, so no sleep.
    {:ok, _} = Worlds.register(%{name: "Orbis", type: "code"})

    assert [%{name: "Orbis"}] = Aleph.Worlds.all(pid)
  end

  test "no worlds → []" do
    pid = start_worlds()
    assert Aleph.Worlds.all(pid) == []
  end
end
