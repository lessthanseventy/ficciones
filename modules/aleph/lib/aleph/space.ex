defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B). **Orbis** (the god-view survey — tertius'
  per-world rollup, the default) leads, then one **World** space per funes world (`Aleph.Worlds`,
  Slice 1) — the machine/stack as a live embedded terminal. World spaces are keyed by the funes
  world id (Phase C1, not a name slug), so `[:orbis, 1]` with the single seeded Tlön world;
  funes-down falls back to the hardcoded Tlön keyed as the sentinel `0` so aleph never boots
  without a World. Sessions is gone (its per-thread native-PTY center folded into the tmux center).
  The
  `Aleph.Panel.Spaces` picker switches the active one; the center renders that space's `surface`.

  A surface is a LIST of sections stacked down the center — usually one (Orbis), but Tlön frames its
  Terminal with two more: WindowBar above, Pulse below. A section is either a bare
  panel module (its data shaped by `Aleph.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Aleph.Panel.Activity
  alias Aleph.Panel.Chorus
  alias Aleph.Panel.Dossier
  alias Aleph.Panel.Health
  alias Aleph.Panel.Leaves
  alias Aleph.Panel.Memory
  alias Aleph.Panel.Pulse
  alias Aleph.Panel.Roster
  alias Aleph.Panel.Stack
  alias Aleph.Panel.Terminal
  alias Aleph.Panel.Triage
  alias Aleph.Panel.WindowBar

  @enforce_keys [:key, :label, :surface]
  defstruct [:key, :label, :surface, :id, left: [], right: [], coworker: nil, roster: []]

  @type surface :: [module() | {module(), atom()}]
  @type t :: %__MODULE__{
          key: :orbis | non_neg_integer(),
          label: String.t(),
          surface: surface(),
          # The funes world id (Phase C1), nil for Orbis. Mirrors `key` for a World space.
          id: non_neg_integer() | nil,
          left: [module()],
          right: [module()],
          # The name of the pi coworker profile this space spawns into its center, or nil for a space
          # with no machine coworker (Aleph.Profiles). Tlön → "tertius".
          coworker: String.t() | nil,
          # The world's full roster (Phase C2/C3 drive the cast from this; carried here so callers
          # don't need a second read).
          roster: [map()]
        }

  @doc """
  The spaces the switcher offers, in picker order — **Orbis first (the default)**, then one World
  space per funes world (`Aleph.Worlds.all/0`, Slice 1 Task B2). `surface` is the center;
  `left`/`right` the situational sidebars. Reads the cached world list; `all/1` is the pure
  derivation over an explicit list (tests inject worlds without the live cache).
  """
  @spec all() :: [t()]
  def all, do: all(fetch_worlds())

  @doc "The picker derived from an explicit world list — `[Orbis | world_spaces(worlds)]`."
  @spec all([map()]) :: [t()]
  def all(worlds), do: [orbis_space() | world_spaces(worlds)]

  defp orbis_space do
    %__MODULE__{
      key: :orbis,
      label: "Orbis",
      # The chorus IS the center now, so thread navigation lives in the feed (the focused
      # thread's block is highlighted) and the left carries presence (IN FLIGHT) instead of a
      # list the middle already shows. TRIAGE below IN FLIGHT shows cross-thread trouble.
      surface: [Chorus],
      left: [Roster, Triage],
      right: [Dossier]
    }
  end

  # One World space per funes world. FALLBACK: an empty list (funes down / unseeded — the seed only
  # runs after home:switch) yields the hardcoded Tlön space, so aleph never boots without a World.
  # With one seeded Tlön world (funes id 1) this is `[:orbis, 1]`.
  defp world_spaces([]), do: [tlon_space()]
  defp world_spaces(worlds), do: Enum.map(worlds, &space_from_world/1)

  # A World space built from a funes world (aleph-shaped `%{id, name, roster, ...}`). Keyed by the
  # funes world id (Phase C1) — not a name slug — so a rename can't break the active session and
  # two worlds can never collide on key. surface/left/right/coworker reproduce the Slice-0 Tlön
  # struct exactly; the coworker is the roster lead's name.
  defp space_from_world(world) do
    %__MODULE__{
      key: world.id,
      id: world.id,
      label: world.name,
      surface: [WindowBar, {Terminal, :machine}, Pulse],
      left: [Stack, Memory],
      right: [Health, Activity, Leaves],
      coworker: lead_coworker(world.roster),
      roster: world.roster
    }
  end

  # The hardcoded Tlön World — the fallback when funes yields no worlds. Its center is literal tmux
  # (an embedded client on the standing `tlon` session, surviving aleph restarts): tertius is window
  # 0, the builder (hronir) and console (uqbar) ride as further windows. WindowBar frames the
  # terminal on top, Pulse (the latest funes event) below — each its own bordered band. Keyed `0`:
  # the sentinel, since real funes world ids start at 1 (never collides with a live world).
  defp tlon_space do
    %__MODULE__{
      key: 0,
      id: 0,
      label: "Tlön",
      surface: [WindowBar, {Terminal, :machine}, Pulse],
      left: [Stack, Memory],
      right: [Health, Activity, Leaves],
      coworker: "tertius"
    }
  end

  # Read the cached worlds, degrading to [] (→ Tlön fallback) if the cache is down mid-render.
  defp fetch_worlds do
    Aleph.Worlds.all()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # The roster lead → center coworker: the first entry's name, tolerating string (JSON) or atom keys.
  defp lead_coworker([entry | _]), do: entry["name"] || entry[:name]
  defp lead_coworker(_), do: nil

  @doc """
  The mode predicate: is `key` a World space (as opposed to `:orbis`)? Replaces the ~40
  `active_key == :tlon` guards the cockpit carried pre-Phase-C1 (Task C1.3) — any funes id,
  including the funes-down fallback sentinel `0`, is a World.
  """
  @spec world?(:orbis | non_neg_integer()) :: boolean()
  def world?(:orbis), do: false
  def world?(key) when is_integer(key), do: true

  @doc "The space after `key` in picker order, wrapping around."
  @spec next(atom() | non_neg_integer()) :: t()
  def next(key), do: step(key, 1)

  @doc "The space before `key` in picker order, wrapping around."
  @spec prev(atom() | non_neg_integer()) :: t()
  def prev(key), do: step(key, -1)

  @doc """
  Look a space up by key, reading the live world cache. Returns `nil` on a miss — **no** silent
  Orbis default (Phase C1: `Space.fetch(:tlon)` used to paper over a stale/unknown key).
  """
  @spec fetch(atom() | non_neg_integer()) :: t() | nil
  def fetch(key), do: fetch(key, all())

  @doc "Pure `fetch/1` over an explicit spaces list — mirrors `all/0`+`all/1` (tests inject spaces)."
  @spec fetch(atom() | non_neg_integer(), [t()]) :: t() | nil
  def fetch(key, spaces), do: Enum.find(spaces, &(&1.key == key))

  defp step(key, delta) do
    spaces = all()
    i = Enum.find_index(spaces, &(&1.key == key)) || 0
    Enum.at(spaces, rem(i + delta + length(spaces), length(spaces)))
  end
end
