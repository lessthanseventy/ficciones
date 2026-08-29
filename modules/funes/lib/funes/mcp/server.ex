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

  alias Funes.MCP.Tool.EditWorkspace
  alias Funes.MCP.Tool.GetBrief
  alias Funes.MCP.Tool.ListWorkspaces
  alias Funes.MCP.Tool.RegisterWorkspace
  alias Funes.MCP.Tool.RemoveWorkspace

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
  component(Funes.MCP.Tool.RecheckFact, name: "recheck_fact")
  component(Funes.MCP.Tool.TrackThread, name: "track_thread")
  component(Funes.MCP.Tool.OpenThread, name: "open_thread")
  component(Funes.MCP.Tool.CloseThread, name: "close_thread")
  component(Funes.MCP.Tool.AdvanceStage, name: "advance_stage")
  component(Funes.MCP.Tool.SubmitReview, name: "submit_review")
  component(Funes.MCP.Tool.SwitchThread, name: "switch_thread")
  component(Funes.MCP.Tool.ConsultPeer, name: "consult_peer")
  component(Funes.MCP.Tool.StaffLeaf, name: "staff_leaf")
  component(Funes.MCP.Tool.SpawnCrew, name: "spawn_crew")
  component(Funes.MCP.Tool.KillCrew, name: "kill_crew")
  component(Funes.MCP.Tool.PresenceThinking, name: "presence_thinking")
  component(Funes.MCP.Tool.PresenceIdle, name: "presence_idle")
  component(Funes.MCP.Tool.ProposeHabit, name: "propose_habit")
  component(GetBrief, name: "get_brief")
  # Transition alias (clarity rename slice E): the same module answers the old name too, so an
  # agent whose prompt still says get_dossier keeps working until the window closes.
  component(GetBrief, name: "get_dossier")
  component(Funes.MCP.Tool.GetFacts, name: "get_facts")
  component(Funes.MCP.Tool.GetMessages, name: "get_messages")
  component(Funes.MCP.Tool.SearchHistory, name: "search_history")
  component(Funes.MCP.Tool.SearchFacts, name: "search_facts")
  component(Funes.MCP.Tool.MachineOverview, name: "machine_overview")
  component(RegisterWorkspace, name: "register_workspace")
  component(ListWorkspaces, name: "list_workspaces")
  component(EditWorkspace, name: "edit_workspace")
  component(RemoveWorkspace, name: "remove_workspace")
  # Transition aliases (clarity rename slice E): the workspace tools answer their old world names too.
  component(RegisterWorkspace, name: "register_world")
  component(ListWorkspaces, name: "list_worlds")
  component(EditWorkspace, name: "edit_world")
  component(RemoveWorkspace, name: "remove_world")
  component(Funes.MCP.Resource.Brief, name: "brief")
  component(Funes.MCP.Resource.Constraints, name: "constraints")
  component(Funes.MCP.Resource.Habits, name: "habits")
end
