defmodule Funes.MCP.Spawn do
  @moduledoc """
  Handing a harness its funes identity (pi doc §2d). A launcher — `funes:spawn`,
  `funes:claude`, the `pi:*` model tasks — opens a fresh thread or JOINS an existing
  one, staffs an agent, and lets the harness authenticate to the sovereign channel.

  Run in the SERVING node (the one holding the `Funes.MCP.Tokens` registry and Bandit):
  a token minted anywhere else dies with its node and 401s. So the launchers reach this
  through `bin/funes rpc` into the LIVE service node.

  Three doors onto the same core (`ensure/3`, which mints nothing):

    * `env/3` / `join/3` — ensure + mint + build the `export FUNES_*` block. A STATIC
      bearer the caller pastes into the harness's env. This is pi's path: its manos
      extension reads `FUNES_TOKEN` once at `session_start`, so the token can't refresh.
    * `mint_for/2` — a FRESH token for an already-ensured (thread, agent), minted on
      demand. This is Claude Code's `headersHelper` path: it runs on every MCP connect
      and reconnect, so the token stays current across a funes restart.

  The launchers call `ensure` once (identity), then either take a static token (`env`/
  `join`) or defer to `mint_for` per connect.
  """
  alias Funes.Channel
  alias Funes.MCP.Tokens
  alias Funes.Repo
  alias Funes.Staff
  alias Funes.Thread

  @typedoc "Open a fresh thread, or join an existing one by id."
  @type thread_ref :: {:open, String.t()} | {:join, integer() | String.t()}

  @doc """
  The spawn-or-join core — mints NOTHING. Resolves `thread_ref` (open a fresh thread
  titled `title`, or join an existing thread by id), ensures the named agent (register
  if new), staffs the thread with it, and returns `{:ok, %{thread: t, agent: a}}`.

  `{:join, id}` on a missing thread returns `{:error, {:no_thread, id}}` — it never
  silently opens a new one, so a typo'd id fails loud instead of forking work.

  Options for a freshly-registered agent: `:mandate` (default "general"), `:engine`
  (default "local"). An existing agent keeps its own — funes has no vendor in the
  design (§8), so `engine` is just a capability handle resolved elsewhere.
  """
  @spec ensure(thread_ref(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Funes.Agent.t()}} | {:error, term()}
  def ensure(thread_ref, agent_name, opts \\ []) when is_binary(agent_name) do
    with {:ok, thread} <- resolve_thread(thread_ref),
         {:ok, agent} <- ensure_agent(agent_name, opts),
         {:ok, thread} <- Staff.assign(thread, agent) do
      {:ok, %{thread: thread, agent: agent}}
    end
  end

  @doc """
  Open a fresh thread titled `title`, ensure `agent_name`, mint a token, and build the
  `export FUNES_*` block. Returns `{:ok, %{thread, agent, token, exports}}`. The static
  bearer path — the caller decides where the block goes (a pi pane's env, stdout).
  """
  @spec env(String.t(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Funes.Agent.t(), token: String.t(), exports: String.t()}}
          | {:error, term()}
  def env(title, agent_name, opts \\ []) when is_binary(title), do: mint_and_export({:open, title}, agent_name, opts)

  @doc "Like `env/3`, but JOIN an existing thread by id instead of opening a fresh one."
  @spec join(integer() | String.t(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Funes.Agent.t(), token: String.t(), exports: String.t()}}
          | {:error, term()}
  def join(thread_id, agent_name, opts \\ []), do: mint_and_export({:join, thread_id}, agent_name, opts)

  @doc """
  A fresh token for an EXISTING (thread, agent) — the Claude-Code `headersHelper` path,
  run on every connect. Both must already exist (the launcher ensured them at start);
  a missing thread is `{:error, {:no_thread, id}}`, a missing agent
  `{:error, {:no_agent, name}}` — never mint against a guess.
  """
  @spec mint_for(integer() | String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def mint_for(thread_id, agent_name) when is_binary(agent_name) do
    with {:ok, thread} <- resolve_thread({:join, thread_id}),
         {:agent, agent} when not is_nil(agent) <- {:agent, Staff.agent_by_name(agent_name)} do
      {:ok, Tokens.mint(thread, agent)}
    else
      {:agent, nil} -> {:error, {:no_agent, agent_name}}
      err -> err
    end
  end

  defp mint_and_export(thread_ref, agent_name, opts) do
    with {:ok, %{thread: thread, agent: agent}} <- ensure(thread_ref, agent_name, opts) do
      token = Tokens.mint(thread, agent)
      {:ok, %{thread: thread, agent: agent, token: token, exports: exports(thread, agent, token)}}
    end
  end

  defp resolve_thread({:open, title}) when is_binary(title), do: Channel.open_thread(%{title: title})

  defp resolve_thread({:join, id}) do
    case Repo.get(Thread, id) do
      nil -> {:error, {:no_thread, id}}
      thread -> {:ok, thread}
    end
  end

  defp ensure_agent(name, opts) do
    case Staff.agent_by_name(name) do
      nil ->
        Staff.register_agent(%{
          name: name,
          mandate: Keyword.get(opts, :mandate, "general"),
          engine: Keyword.get(opts, :engine, "local")
        })

      agent ->
        {:ok, agent}
    end
  end

  defp exports(thread, agent, token) do
    port = Application.get_env(:funes, :mcp_port, 4040)

    """
    export FUNES_MCP_URL="http://127.0.0.1:#{port}/mcp"
    export FUNES_TOKEN="#{token}"
    export FUNES_THREAD="#{thread.id}"
    export FUNES_AUTHOR="#{agent.name}"\
    """
  end
end
