defmodule Funes.MCP.Tokens do
  @moduledoc """
  The identity seam of the sovereign channel (pi doc §2a). A token is minted IN
  this node — by the arbiter at spawn, or by the operator in iex for a hand-run
  session — and binds an MCP connection to its (thread, agent). Every tool then
  reads identity from the connection's claims, never from a call parameter, so
  banking onto the wrong thread is unrepresentable rather than merely discouraged.

  Deliberately EPHEMERAL: bindings live in this process, and a node restart
  invalidates every token. That is the honest failure mode — the agent's next
  call 401s and it says so — never a durable credential store (how a machine
  authenticates is local configuration, §8, and a stale grant that outlives its
  session is the zombie problem wearing a lanyard).

  `register` claims a session and binds it here (`bind_session/2`), so later
  calls resolve to a full identity including the session to keep warm.
  """
  use GenServer

  alias Funes.{Agent, Thread}

  @type binding :: %{
          thread_id: integer(),
          agent_id: integer(),
          agent: String.t(),
          session_id: integer() | nil
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Mint a token binding (thread, agent). Returns the url-safe token string."
  @spec mint(Thread.t(), Agent.t()) :: String.t()
  def mint(%Thread{} = thread, %Agent{} = agent) do
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    binding = %{
      thread_id: thread.id,
      agent_id: agent.id,
      agent: agent.name,
      session_id: nil
    }

    :ok = GenServer.call(__MODULE__, {:put, token, binding})
    token
  end

  @doc "The binding behind a token, or `:error` for one this node never minted."
  @spec resolve(String.t()) :: {:ok, binding()} | :error
  def resolve(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:resolve, token})
  end

  @doc "Attach the registered session to a token's binding. `:error` on an unknown token."
  @spec bind_session(String.t(), integer()) :: :ok | :error
  def bind_session(token, session_id) when is_binary(token) do
    GenServer.call(__MODULE__, {:bind_session, token, session_id})
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:put, token, binding}, _from, state) do
    {:reply, :ok, Map.put(state, token, binding)}
  end

  def handle_call({:resolve, token}, _from, state) do
    case Map.fetch(state, token) do
      {:ok, binding} -> {:reply, {:ok, binding}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:bind_session, token, session_id}, _from, state) do
    case Map.fetch(state, token) do
      {:ok, binding} ->
        {:reply, :ok, Map.put(state, token, %{binding | session_id: session_id})}

      :error ->
        {:reply, :error, state}
    end
  end
end
