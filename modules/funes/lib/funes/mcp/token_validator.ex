defmodule Funes.MCP.TokenValidator do
  @moduledoc """
  Resolves a bearer token against `Funes.MCP.Tokens` — the whole authorization
  model on a single-human machine: a token this node minted, or 401. The claims
  carry the binding (thread, agent, session) every tool reads from its frame,
  plus the token itself so `register` can bind its session back here. `aud`
  mirrors the configured resource because anubis validates audience
  unconditionally; there is no `exp` — a token dies with the node, not a clock.
  """
  @behaviour Anubis.Server.Authorization.Validator

  alias Funes.MCP.Tokens

  @impl true
  def validate_token(token, config) do
    case Tokens.resolve(token) do
      {:ok, binding} ->
        {:ok,
         %{
           "sub" => binding.agent,
           "aud" => config.resource,
           "thread_id" => binding.thread_id,
           "agent_id" => binding.agent_id,
           "session_id" => binding.session_id,
           "token" => token
         }}

      :error ->
        {:error, :unknown_token}
    end
  end
end
