defmodule Funes.MCP.Server do
  @moduledoc """
  The sovereign channel (pi doc §2a): funes' MCP server. Every tool and resource
  is a thin caller of the contexts — never a second writer to the DB (§10) — and
  identity rides the CONNECTION: the bearer token (minted in-node by
  `Funes.MCP.Tokens`) resolves to a (thread, agent, session) binding on every
  request, so no tool takes a thread parameter. The protocol lifecycle —
  JSON-RPC, sessions, version negotiation, auth — is anubis', a library that
  tracks the MCP spec so this seam cannot drift from it under our hands.

  Served loopback-only by Bandit (`Funes.Application`, opt-in via `:start_mcp`);
  being MCP, it serves ANY agent — pi today, another tomorrow.
  """
  use Anubis.Server,
    name: "funes",
    version: "0.1.0",
    capabilities: [:tools, :resources],
    authorization: [
      authorization_servers: ["http://127.0.0.1"],
      resource: "http://127.0.0.1/funes",
      validator: {Funes.MCP.TokenValidator, []}
    ]

  component(Funes.MCP.Tool.Register, name: "register")
  component(Funes.MCP.Tool.PostMessage, name: "post_message")
  component(Funes.MCP.Tool.BankFact, name: "bank_fact")
  component(Funes.MCP.Tool.RaiseIssue, name: "raise_issue")
  component(Funes.MCP.Tool.RecordDone, name: "record_done")
  component(Funes.MCP.Tool.AddTodo, name: "add_todo")
  component(Funes.MCP.Tool.CompleteTodo, name: "complete_todo")
  component(Funes.MCP.Tool.RaiseQuestion, name: "raise_question")
  component(Funes.MCP.Tool.ResolveQuestion, name: "resolve_question")
  component(Funes.MCP.Tool.RecordCheck, name: "record_check")
  component(Funes.MCP.Tool.OpenThread, name: "open_thread")
  component(Funes.MCP.Tool.CloseThread, name: "close_thread")
  component(Funes.MCP.Tool.GetDossier, name: "get_dossier")
  component(Funes.MCP.Tool.GetFacts, name: "get_facts")
  component(Funes.MCP.Tool.GetMessages, name: "get_messages")
  component(Funes.MCP.Resource.Dossier, name: "dossier")
  component(Funes.MCP.Resource.Constraints, name: "constraints")
end
