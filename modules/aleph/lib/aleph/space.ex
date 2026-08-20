defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B). Each space is a different app over the
  same substrate: **Orbis** (the thread/message chorus, the default), **Sessions** (the live
  embedded-terminal view), and **Tlön** (the META space — the machine/stack as a whole, not a
  project). The `Aleph.Panel.Spaces` picker switches the active one; the center renders that
  space's `surface`.

  A surface is a LIST of sections stacked down the center (one per space today). A section is either a
  bare panel module (its data shaped by `Aleph.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Aleph.Panel.Chorus
  alias Aleph.Panel.Dossier
  alias Aleph.Panel.Health
  alias Aleph.Panel.Memory
  alias Aleph.Panel.Orbis
  alias Aleph.Panel.Roster
  alias Aleph.Panel.Stack
  alias Aleph.Panel.Terminal
  alias Aleph.Panel.ThreadList
  alias Aleph.Panel.Triage

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
  The spaces the switcher offers, in picker order — **Orbis first (the default)**. Deliberately
  hardcoded for now; the design ships one set and *designs toward* user config (§3). `surface` is
  the center; `left`/`right` the situational sidebars.
  """
  @spec all() :: [t()]
  def all do
    [
      %__MODULE__{
        key: :orbis,
        label: "Orbis",
        # The chorus IS the center now, so thread navigation lives in the feed (the focused
        # thread's block is highlighted) and the left carries presence (IN FLIGHT) instead of a
        # list the middle already shows. TRIAGE below IN FLIGHT shows cross-thread trouble.
        surface: [Chorus],
        left: [Roster, Triage],
        right: [Dossier]
      },
      %__MODULE__{
        key: :sessions,
        label: "Sessions",
        surface: [{Terminal, :terminal}],
        # The annotated ThreadList *is* the merged IN FLIGHT + THREADS: one list, agents folded in
        # (Addendum §A). Picking a thread here swaps the center's live coworker session.
        left: [ThreadList],
        right: [Dossier]
      },
      %__MODULE__{
        # Tlön: the center is literal tmux — an embedded client on the standing `tlon` session, so it
        # survives aleph restarts. The center coworker (tertius) is window 0; the builder (hronir) and
        # console (uqbar) ride as further windows, which aleph renders as the tab strip.
        key: :tlon,
        label: "Tlön",
        surface: [{Terminal, :machine}],
        # The study/act column: Commits (git changelog, was Stack) over Memory (what funes knows —
        # coverage + the always-loaded floor + pending habits to approve). Habits folded INTO Memory;
        # Settings is now the `m` keybind / a modal, not an always-on pane.
        left: [Stack, Memory],
        # ORBIS — the machine rollup (leaves' lead/status/conflicts). Health becomes the status bar
        # in the visual-cleanup pass; Orbis becomes Leaves when that pane lands.
        right: [Health, Orbis],
        # The center coworker: the `tertius` profile (Orbis Tertius meta agent). See Aleph.Profiles.
        coworker: "tertius"
      }
    ]
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
