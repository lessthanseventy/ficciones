defmodule Funes.MCP.Tool do
  @moduledoc """
  The slice-1 tool surface (pi doc §2a/§5.1) — every tool a thin caller of the
  contexts, never a second writer (§10). Identity (thread, agent, session) rides
  the connection via `Funes.MCP.Identity`, so no tool takes a thread parameter:
  misdirection is unrepresentable. Grouped in one file the way `Funes.Arbiter`
  groups its backends — one seam, several small faces.
  """

  @doc "A changeset's errors as one tool-error sentence."
  def changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end

defmodule Funes.MCP.Tool.Register do
  @moduledoc """
  Claim a live session for this connection's (thread, agent). Call once at
  session start. Supersedes any crashed predecessor's session — the zombie guard.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.MCP.Identity
  alias Funes.MCP.Tokens
  alias Funes.Staff

  schema do
    field :pane_ref, :string, description: "Opaque pane handle (e.g. $TMUX_PANE)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    # The binding came from real rows, so an FK failure here is a bug that raises.
    {:ok, session} =
      Staff.start_session(%{
        agent_id: identity.agent_id,
        thread_id: identity.thread_id,
        pane_ref: params[:pane_ref]
      })

    :ok = Tokens.bind_session(identity.token, session.id)

    payload = %{
      "session_id" => session.id,
      "agent" => identity.agent,
      "thread_id" => identity.thread_id
    }

    {:reply, Response.json(Response.tool(), payload), frame}
  end
end

defmodule Funes.MCP.Tool.PostMessage do
  @moduledoc """
  Post to this connection's thread — talk on your thread, don't work in the void.
  The author is the bound agent; a reply targets the quoted message's author.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Channel
  alias Funes.MCP

  schema do
    field :body, :string, required: true
    field :reply_to, :integer, description: "Message id this replies to"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Channel.post(%{
           thread_id: identity.thread_id,
           author: identity.agent,
           body: params[:body],
           reply_to: params[:reply_to]
         }) do
      {:ok, message} ->
        {:reply, Response.json(Response.tool(), %{"message_id" => message.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Funes.MCP.Tool.BankFact do
  @moduledoc """
  Bank a durable fact on this thread. Your own finding is `derived` — pass
  `check_cmd` when the claim is reproducible, or it ranks as an unverified
  opinion. To bank the operator's words as a `stated` fact, pass `from_message`
  (his message id): the fact quotes it verbatim. Never paraphrase him into text.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.MCP

  schema do
    field :kind, :enum, values: ["decision", "constraint", "learned"], required: true

    field :text, :string, description: "The single claim (omit when from_message quotes the operator)"

    field :check_cmd, :string, description: "Command that re-runs/verifies the claim"

    field :from_message, :integer, description: "Operator message id to quote verbatim as a STATED fact"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    result =
      case Map.get(params, :from_message) do
        nil -> bank_derived(params, identity)
        message_id -> bank_stated(message_id, params, identity)
      end

    case result do
      {:ok, fact} ->
        payload = %{"fact_id" => fact.id, "provenance" => fact.provenance}
        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp bank_derived(%{text: text} = params, identity) when is_binary(text) do
    %{
      thread_id: identity.thread_id,
      kind: params.kind,
      text: text,
      provenance: "derived",
      check_cmd: Map.get(params, :check_cmd),
      source_session_id: identity.session_id
    }
    |> Dossier.bank_fact()
    |> normalize()
  end

  defp bank_derived(_params, _identity), do: {:error, "text is required unless from_message quotes the operator"}

  defp bank_stated(message_id, params, identity) do
    message = Channel.message(message_id)

    cond do
      is_nil(message) ->
        {:error, "no message ##{message_id}"}

      message.thread_id != identity.thread_id ->
        {:error, "message ##{message_id} is not on this connection's thread"}

      true ->
        message
        |> Dossier.bank_stated_fact(%{
          kind: params.kind,
          check_cmd: Map.get(params, :check_cmd),
          source_session_id: identity.session_id
        })
        |> normalize()
    end
  end

  defp normalize({:ok, fact}), do: {:ok, fact}

  defp normalize({:error, :not_the_operator}),
    do: {:error, "stated facts quote the operator's own words; that message is not his"}

  defp normalize({:error, %Ecto.Changeset{} = cs}), do: {:error, MCP.Tool.changeset_error(cs)}
end

defmodule Funes.MCP.Tool.RaiseIssue do
  @moduledoc """
  Record a defect in the STACK itself — the machine's own tracker, never product
  work or a task question (a knowledge gap is a question; being stuck is a
  message). This thread is recorded as the discovery site.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Dossier
  alias Funes.MCP

  schema do
    field :summary, :string, required: true
    field :evidence, :string, description: "Where the evidence is"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.raise_issue(%{
           thread_id: identity.thread_id,
           summary: params[:summary],
           evidence: Map.get(params, :evidence),
           found_by: identity.agent
         }) do
      {:ok, issue} ->
        {:reply, Response.json(Response.tool(), %{"issue_id" => issue.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Funes.MCP.Tool.RecordDone do
  @moduledoc """
  Record work landed on this thread. Evidence is REQUIRED — the command run, the
  commit, the passing gate. A claim that something works is backed by having run
  it.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Dossier
  alias Funes.MCP

  schema do
    field :text, :string, required: true, description: "What shipped, one line"

    field :evidence, :string,
      required: true,
      description: "What proves it: the command and its result, a commit, a green gate"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.record_event(%{
           thread_id: identity.thread_id,
           kind: "work_landed",
           detail: %{"summary" => params[:text], "evidence" => params[:evidence]}
         }) do
      {:ok, event} ->
        {:reply, Response.json(Response.tool(), %{"event_id" => event.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Funes.MCP.Tool.GetDossier do
  @moduledoc """
  This thread's brief: goal, lead, learnings (with certainty), blockers, shipped,
  chatter — each capped WITH a count. Use get_facts to read past a cap.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Board
  alias Funes.MCP
  alias Funes.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)
    brief = %Thread{id: identity.thread_id} |> Board.in_scope() |> MCP.Brief.scope()
    {:reply, Response.json(Response.tool(), brief), frame}
  end
end

defmodule Funes.MCP.Tool.GetFacts do
  @moduledoc "Every fact on this thread, newest first — the full read past the brief's cap."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Dossier
  alias Funes.MCP
  alias Funes.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)

    facts =
      %Thread{id: identity.thread_id}
      |> Dossier.facts_for_thread()
      |> Enum.map(&MCP.Brief.fact/1)

    {:reply, Response.json(Response.tool(), facts), frame}
  end
end

defmodule Funes.MCP.Tool.GetMessages do
  @moduledoc "This thread's recent messages in chat order, capped by limit."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Funes.Channel
  alias Funes.MCP
  alias Funes.Thread

  schema do
    field :limit, :integer, default: 50
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    messages =
      %Thread{id: identity.thread_id}
      |> Channel.recent_messages(params[:limit] || 50)
      |> Enum.map(&MCP.Brief.message/1)

    {:reply, Response.json(Response.tool(), messages), frame}
  end
end
