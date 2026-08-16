defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B; renamed from "workspace," which collided
  with tmux and Herdr). Each space is a different app over the same substrate: **Comms** (the
  thread/message chorus, the default), **Sessions** (the live embedded-terminal view), and
  **Tlön** (the META space — the machine/stack as a whole, not a project). The `Aleph.Panel.Spaces`
  picker switches the active one; the center renders that space's `surface`.

  A surface is `{panel_module, data_key}` — the Cockpit resolves `data_key` to the funes read it
  feeds the panel (so a space stays plain data, holding no logic of its own). The left/right slots
  list the situational panels that ride along with the space.
  """

  alias Aleph.Panel.Chorus
  alias Aleph.Panel.Conversation
  alias Aleph.Panel.Dossier
  alias Aleph.Panel.Roster
  alias Aleph.Panel.ThreadList

  @enforce_keys [:key, :label, :surface]
  defstruct [:key, :label, :surface, left: [], right: []]

  @type surface :: {module(), atom()}
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
        surface: {Chorus, :chorus},
        left: [Roster],
        right: [Dossier]
      },
      %__MODULE__{
        key: :sessions,
        label: "Sessions",
        surface: {Aleph.Panel.Terminal, :terminal},
        # The annotated ThreadList *is* the merged IN FLIGHT + THREADS: one list, agents folded in
        # (Addendum §A). Picking a thread here swaps the center's live coworker session.
        left: [ThreadList],
        right: [Dossier]
      },
      %__MODULE__{
        # Tlön — the META space: the machine/stack as a whole, not a project. Where you work on the
        # env itself (nix, the funes/aleph/manos stack, tool changelogs). Shape still coalescing —
        # this is a transitional placeholder over the same panels; the distinct machine-state view
        # (stack activity, changelogs, signals) is the next design pass.
        key: :tlon,
        label: "Tlön",
        surface: {ThreadList, :issues},
        left: [Conversation],
        right: [Dossier]
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
