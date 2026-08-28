defmodule Aleph.TestWorlds do
  @moduledoc """
  The world-list fixture for suites that render/drive a World space. The hardcoded
  fallback World is gone (reshape slice A: funes self-seeds, aleph renders funes-down
  honestly), so a test that needs a World pushes one through `Aleph.Worlds.all/0`'s
  cache-down seam — process-scoped (`Process.put`), so async suites never race.

  `put/0` installs the classic one-world fixture (id 0 — what the old fallback keyed,
  so existing `active_key: 0` / `aleph-world-0` expectations hold); `put/1` any list.
  """

  @world %{
    id: 0,
    name: "Tlön",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "builder", "name" => "hronir"}
    ]
  }

  @doc "The one-world fixture row itself (for asserting against)."
  def world, do: @world

  @doc "Install the fixture world list for the calling process."
  def put(worlds \\ [@world]) do
    Process.put(:aleph_worlds, worlds)
    :ok
  end
end
