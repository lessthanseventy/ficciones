defmodule Aleph.Sessions do
  @moduledoc """
  The live session terminals — one `Aleph.Terminal` per thread, the aleph hub's replacement for
  tmux panes. A registry over a `DynamicSupervisor`: `ensure/2` starts a terminal for a thread (or
  returns the existing one), `terminal/1` looks it up, `all/0` lists them (for the roster). A
  terminal that exits (the child process ended) is dropped, so the map is never stale — the
  §3 "ask, don't mirror" rule applied to sessions: a dead pane leaves no ghost row.

  Terminals run under a DynamicSupervisor (not linked to this registry), so one crashing never
  takes the registry or the cockpit down; this GenServer only monitors them to keep the map honest.
  """
  use GenServer

  alias Aleph.Terminal

  @sup Aleph.TerminalSup

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Ensure a terminal for `thread_id`, starting one with `opts` if absent. `{:ok, pid}`."
  def ensure(thread_id, opts), do: GenServer.call(__MODULE__, {:ensure, thread_id, opts})

  @doc "The terminal pid for a thread, or nil."
  def terminal(thread_id), do: GenServer.call(__MODULE__, {:terminal, thread_id})

  @doc "All live session terminals as `%{thread_id => pid}`."
  def all, do: GenServer.call(__MODULE__, :all)

  @impl true
  def init(:ok), do: {:ok, %{by_thread: %{}, by_ref: %{}}}

  @impl true
  def handle_call({:ensure, thread_id, opts}, _from, state) do
    case Map.get(state.by_thread, thread_id) do
      pid when is_pid(pid) ->
        {:reply, {:ok, pid}, state}

      nil ->
        case DynamicSupervisor.start_child(@sup, {Terminal, opts}) do
          {:ok, pid} ->
            ref = Process.monitor(pid)

            state = %{
              state
              | by_thread: Map.put(state.by_thread, thread_id, pid),
                by_ref: Map.put(state.by_ref, ref, thread_id)
            }

            {:reply, {:ok, pid}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:terminal, thread_id}, _from, state), do: {:reply, Map.get(state.by_thread, thread_id), state}

  def handle_call(:all, _from, state), do: {:reply, state.by_thread, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.by_ref, ref) do
      {nil, _by_ref} -> {:noreply, state}
      {thread_id, by_ref} -> {:noreply, %{state | by_thread: Map.delete(state.by_thread, thread_id), by_ref: by_ref}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
