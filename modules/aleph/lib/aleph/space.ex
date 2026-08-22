defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B). **Orbis** (the god-view survey — tertius'
  per-world rollup, the default) leads, then one **World** space per funes world (`Aleph.Worlds`,
  Slice 1) — the machine/stack as a live embedded terminal. With the single seeded Tlön world this
  is the Slice-0 `[:orbis, :tlon]`; funes-down falls back to the hardcoded Tlön so aleph never boots
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
  defstruct [:key, :label, :surface, left: [], right: [], coworker: nil]

  @type surface :: [module() | {module(), atom()}]
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t(),
          surface: surface(),
          left: [module()],
          right: [module()],
          # The name of the pi coworker profile this space spawns into its center, or nil for a space
          # with no machine coworker (Aleph.Profiles). Tlön → "tertius".
          coworker: String.t() | nil
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
  # With one seeded Tlön world this is structurally identical to the Slice-0 `[:orbis, :tlon]`.
  defp world_spaces([]), do: [tlon_space()]
  defp world_spaces(worlds), do: Enum.map(worlds, &space_from_world/1)

  # A World space built from a funes world (aleph-shaped `%{name, roster, ...}`). The `:tlon` key
  # requirement (the whole cockpit still keys off the `:tlon` atom — de-singletoning is Phase C)
  # is met by the name→key slug: "Tlön" → :tlon. surface/left/right/coworker reproduce the
  # Slice-0 Tlön struct exactly; the coworker is the roster lead's name.
  defp space_from_world(world) do
    %__MODULE__{
      key: slug(world.name),
      label: world.name,
      surface: [WindowBar, {Terminal, :machine}, Pulse],
      left: [Stack, Memory],
      right: [Health, Activity, Leaves],
      coworker: lead_coworker(world.roster)
    }
  end

  # The hardcoded Tlön World — the fallback when funes yields no worlds. Its center is literal tmux
  # (an embedded client on the standing `tlon` session, surviving aleph restarts): tertius is window
  # 0, the builder (hronir) and console (uqbar) ride as further windows. WindowBar frames the
  # terminal on top, Pulse (the latest funes event) below — each its own bordered band.
  defp tlon_space do
    %__MODULE__{
      key: :tlon,
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

  # name → space key. Downcase, then NFD-decompose and strip combining marks so ö→o (⇒ "Tlön" keys
  # as :tlon exactly, the atom the cockpit still hardcodes); non-alphanumerics collapse to "_".
  defp slug(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> String.to_atom()
  end

  @doc "The space after `key` in picker order, wrapping around."
  @spec next(atom()) :: t()
  def next(key), do: step(key, 1)

  @doc "The space before `key` in picker order, wrapping around."
  @spec prev(atom()) :: t()
  def prev(key), do: step(key, -1)

  @doc "Look a space up by key; the first space (Orbis) is the default."
  @spec fetch(atom()) :: t()
  def fetch(key), do: Enum.find(all(), List.first(all()), &(&1.key == key))

  defp step(key, delta) do
    spaces = all()
    i = Enum.find_index(spaces, &(&1.key == key)) || 0
    Enum.at(spaces, rem(i + delta + length(spaces), length(spaces)))
  end
end
