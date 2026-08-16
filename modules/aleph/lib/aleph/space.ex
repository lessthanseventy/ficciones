defmodule Aleph.Space do
  @moduledoc """
  A **space** is a named lens over funes — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B; renamed from "workspace," which collided
  with tmux and Herdr). Each space is a different app over the same substrate: **Comms** (the
  thread/message rollup, the default), **Sessions** (the expanded live coworker-session view), and
  **Issues** (a thin list). The `Aleph.Panel.Spaces` picker switches the active one; the center
  renders that space's `surface`.

  A surface is `{panel_module, data_key}` — the Cockpit resolves `data_key` to the funes read it
  feeds the panel (so a space stays plain data, holding no logic of its own). The left/right slots
  list the situational panels that ride along with the space.
  """

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
        surface: {Aleph.Panel.Conversation, :conversation},
        left: [Aleph.Panel.ThreadList],
        right: [Aleph.Panel.Dossier]
      },
      %__MODULE__{
        key: :sessions,
        label: "Sessions",
        surface: {Aleph.Panel.Session, :session},
        # The annotated ThreadList *is* the merged IN FLIGHT + THREADS: one list, agents folded in
        # (Addendum §A). Picking a thread here swaps the center's live coworker session.
        left: [Aleph.Panel.ThreadList],
        right: [Aleph.Panel.Dossier]
      },
      %__MODULE__{
        key: :issues,
        label: "Issues",
        surface: {Aleph.Panel.ThreadList, :issues},
        left: [Aleph.Panel.Conversation],
        right: [Aleph.Panel.Dossier]
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
