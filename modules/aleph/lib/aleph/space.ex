defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B; renamed from "workspace," which collided
  with tmux and Herdr). Each space is a different app over the same substrate: **Comms** (the
  thread/message chorus, the default), **Sessions** (the live embedded-terminal view), and
  **Tlön** (the META space — the machine/stack as a whole, not a project). The `Aleph.Panel.Spaces`
  picker switches the active one; the center renders that space's `surface`.

  A surface is a LIST of sections stacked down the center — one for most spaces, two for
  Tlön (the pi machine coworker over the claude escalation pane). A section is either a
  bare panel module (its data shaped by `Aleph.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Aleph.Panel.Chorus
  alias Aleph.Panel.Dossier
  alias Aleph.Panel.Roster
  alias Aleph.Panel.Terminal
  alias Aleph.Panel.ThreadList

  @enforce_keys [:key, :label, :surface]
  defstruct [:key, :label, :surface, left: [], right: []]

  @type surface :: [module() | {module(), atom()}]
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t(),
          surface: surface(),
          left: [module()],
          right: [module()]
        }

  @doc """
  The spaces the switcher offers, in picker order — **Comms first (the default)**. Deliberately
  hardcoded for now; the design ships one set and *designs toward* user config (§3). `surface` is
  the center; `left`/`right` the situational sidebars.
  """
  @spec all() :: [t()]
  def all do
    [
      %__MODULE__{
        key: :comms,
        label: "Comms",
        # The chorus (all threads, one feed) IS the center now, so the threads leave the left —
        # navigating them lives in the feed (the focused thread's block is highlighted). The left
        # carries who's live (IN FLIGHT), the useful sidebar for a chat: presence, not a list the
        # middle already shows.
        surface: [Chorus],
        left: [Roster],
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
        # Tlön — the META space: the machine/stack as a whole, not a project. The center is
        # LITERAL tmux: an embedded client attached to the standing `tlon` session, so the
        # machine workspace gets tmux's own windows/tabs, mouse, resurrect/plugins and the
        # user's config — and it SURVIVES aleph restarts (the session outlives the client).
        # pi lives in window 0 (spawned with the session); claude is a lazily-summoned window
        # (`Ctrl+B o`), so entering Tlön never drains the scarce bucket by itself. The left is
        # STACK (recent ficciones commits); the right is TOOLS (installed versions). The
        # multi-section surface machinery (a LIST here) stays for future split centers.
        key: :tlon,
        label: "Tlön",
        surface: [{Terminal, :machine}],
        left: [Aleph.Panel.Stack],
        right: [Aleph.Panel.Tools]
      }
    ]
  end

  @doc "The space after `key` in picker order, wrapping around."
  @spec next(atom()) :: t()
  def next(key), do: step(key, 1)

  @doc "The space before `key` in picker order, wrapping around."
  @spec prev(atom()) :: t()
  def prev(key), do: step(key, -1)

  @doc "Look a space up by key; the first space (Comms) is the default."
  @spec fetch(atom()) :: t()
  def fetch(key), do: Enum.find(all(), List.first(all()), &(&1.key == key))

  defp step(key, delta) do
    spaces = all()
    i = Enum.find_index(spaces, &(&1.key == key)) || 0
    Enum.at(spaces, rem(i + delta + length(spaces), length(spaces)))
  end
end
