defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B). **Orbis** (the god-view survey — tertius'
  per-world rollup, the default) leads, then one **World** space per funes world (`Aleph.Worlds`,
  Slice 1) — the machine/stack as a live embedded terminal. World spaces are keyed by the funes
  world id (Phase C1, not a name slug), so `[:orbis, 1]` with the single seeded world;
  funes-down degrades to Orbis alone — funes self-seeds a default workspace at boot
  (Funes.Bootstrap), so no fallback World is fabricated here (reshape slice A).
  Sessions is gone (its per-thread native-PTY center folded into the tmux center).
  The
  `Aleph.Panel.Sidebar` workspace nav switches the active one; the center renders that space's `surface`.

  A surface is a LIST of sections stacked down the center — usually one (Orbis), but Tlön frames its
  Terminal with two more: WindowBar above, Pulse below. A section is either a bare
  panel module (its data shaped by `Aleph.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Aleph.Panel.Activity
  alias Aleph.Panel.Chorus
  alias Aleph.Panel.Crew
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

  # One World space per funes world. An empty list means funes is genuinely down — the app
  # self-seeds a default workspace at boot (Funes.Bootstrap), so no fake World is fabricated
  # here (reshape slice A); the picker degrades to Orbis alone.
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
      # Leaves IS the unified thread list now (reshape slice C — tracked rows chip their
      # stage inline), so the separate WORKLINES pane is gone from the carousel.
      right: [Health, Crew, Activity, Leaves],
      coworker: lead_coworker(world.roster),
      roster: world.roster
    }
  end

  # Read the cached worlds, degrading to [] (→ Orbis-only picker) if the cache is down mid-render.
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
  including the funes-down fallback sentinel `0`, is a World. A `defguard` (not a plain function)
  so cockpit/keymap clause heads can gate directly on it (`when Space.world?(key)`) — callers must
  `require Aleph.Space` (a macro, unlike an ordinary `def`).
  """
  # A defguard evaluates to `false` (never raises) for any non-integer, non-`:orbis` key — a stray
  # `:tlon` no longer fails loudly, it just reads as "not a World".
  defguard world?(key) when is_integer(key)

  @doc """
  The single World space in Slice 1 — the C1 bridge for call sites that used to hardcode
  `fetch(:tlon)`/`:tlon`, before multiplicity. Returns the first world-keyed space, or `nil`
  when funes yields no world (even the fallback keys a world, so `nil` is funes-genuinely-empty).
  C2 replaces these call sites with the ACTIVE world once there can be more than one.
  """
  @spec first_world() :: t() | nil
  def first_world, do: Enum.find(all(), &world?(&1.key))

  @doc "The space after `key` in picker order, wrapping around."
  @spec next(:orbis | non_neg_integer()) :: t()
  def next(key), do: step(key, 1)

  @doc "The space before `key` in picker order, wrapping around."
  @spec prev(:orbis | non_neg_integer()) :: t()
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

  @doc """
  The right column actually on screen (design 2026-08-23): the FIRST right panel pinned
  (HEALTH), plus the `view`-indexed one of the rest — the carousel, CREW default at index 0.
  Also the exact shape the Focus SM navigates, so View/keymap/cockpit can never disagree.
  """
  @spec visible_right(t(), integer()) :: [module() | {module(), atom()}]
  def visible_right(%__MODULE__{right: []}, _view), do: []
  def visible_right(%__MODULE__{right: [pinned]}, _view), do: [pinned]

  # Integer.mod, not rem: the public contract wraps negative views too.
  def visible_right(%__MODULE__{right: [pinned | carousel]}, view),
    do: [pinned, Enum.at(carousel, Integer.mod(view, length(carousel)))]

  @doc "The carousel members (everything after the pinned head) — the tab strip's panels."
  @spec carousel(t()) :: [module() | {module(), atom()}]
  def carousel(%__MODULE__{right: [_pinned | rest]}), do: rest
  def carousel(_space), do: []
end
