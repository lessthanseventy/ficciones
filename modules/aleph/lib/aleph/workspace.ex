defmodule Aleph.Workspace do
  @moduledoc """
  A **workspace** is a named environment — *what's in the middle* and the panels around it. It
  is Herdr's "workspace type" idea rebuilt clean (design §3/§5): a composition you pick, not a
  mirrored-state layer. The top-left `Aleph.Panel.Workspaces` picker switches the active one;
  the center renders that workspace's `surface`.

  A surface is `{panel_module, data_key}` — the Cockpit resolves `data_key` to the funes read it
  feeds the panel (so a workspace stays plain data, holding no logic of its own). The left/right
  slots list the situational panels that ride along with the mode.
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
  The workspaces the cockpit offers, in picker order. Deliberately hardcoded for now — the
  design ships one composition and *designs toward* user config (§3); this is the shape that
  config later fills. `surface` is the center; `left`/`right` the situational sidebars.
  """
  @spec all() :: [t()]
  def all do
    [
      %__MODULE__{
        key: :terminal,
        label: "Terminal",
        surface: {Aleph.Panel.Session, :session},
        left: [Aleph.Panel.Roster, Aleph.Panel.Conversation],
        right: [Aleph.Panel.Dossier]
      },
      %__MODULE__{
        key: :chat,
        label: "Chat",
        surface: {Aleph.Panel.Conversation, :conversation},
        left: [Aleph.Panel.Roster, Aleph.Panel.ThreadList],
        right: [Aleph.Panel.Dossier]
      },
      %__MODULE__{
        key: :tickets,
        label: "Tickets",
        surface: {Aleph.Panel.ThreadList, :tickets},
        left: [Aleph.Panel.Roster, Aleph.Panel.Conversation],
        right: [Aleph.Panel.Dossier]
      }
    ]
  end

  @doc "The workspace after `key` in picker order, wrapping around."
  @spec next(atom()) :: t()
  def next(key), do: step(key, 1)

  @doc "The workspace before `key` in picker order, wrapping around."
  @spec prev(atom()) :: t()
  def prev(key), do: step(key, -1)

  @doc "Look a workspace up by key; the first workspace is the default."
  @spec fetch(atom()) :: t()
  def fetch(key), do: Enum.find(all(), List.first(all()), &(&1.key == key))

  defp step(key, delta) do
    ws = all()
    i = Enum.find_index(ws, &(&1.key == key)) || 0
    Enum.at(ws, rem(i + delta + length(ws), length(ws)))
  end
end
