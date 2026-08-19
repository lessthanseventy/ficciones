defmodule Funes do
  @moduledoc """
  The boundary of the funes system (enforced by the `:boundary` compiler — a violation is a
  compile warning, and the gate runs `--warnings-as-errors`, so reaching into a non-exported
  module fails `mise run check`).

  The exports below ARE funes' public surface — what a consumer (aleph, an MCP adapter) may
  call. Everything else (`Repo`, the schemas' changesets, `Switchboard`, `Agent`, `Session`,
  the event/fact/issue internals) is this module's own business: reach for it from outside and
  the build says no. Widening the surface is a one-line diff HERE, which is the point — the
  surface creeps only on purpose, reviewed in this file's history.
  """

  use Boundary,
    deps: [],
    exports: [
      # The channel: threads, messages, the chorus — the one conversational API.
      Channel,
      # Pub/sub topics for live surfaces (aleph subscribes; announce stays internal callers').
      Bus,
      # Read models a cockpit renders: who's working, what's known, what's in scope.
      Staff,
      Board,
      Dossier,
      Presence,
      # The agent-to-agent consult (ask a peer; the answer is mirrored back).
      Consult,
      # Migration pre-flight (aleph.run refuses to boot a behind db).
      Doctor,
      # Identity minting for spawned harnesses (the funes-citizen handshake).
      MCP.Spawn,
      # The arbiter behaviour a host implements (aleph's terminal-writing arbiter).
      Arbiter,
      # Structs read by consumers (pattern-matched, never changeset-built from outside).
      Thread,
      Message
    ]

  @doc "The handle of the agent staffed on a thread (its lead), or nil."
  defdelegate thread_lead(thread_id), to: Funes.Channel

  @doc "Staff a thread with an agent by handle — resolves the agent + thread and assigns."
  defdelegate assign_lead(thread_id, handle), to: Funes.Channel
end
