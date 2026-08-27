defmodule Funes.Maintain.Monitor do
  @moduledoc """
  The Maintain back-edge (worklines slice 6): deterministic control-band sweeps with NO
  human in the invocation path — yet nothing it does is unsupervised, because every action
  is a nag message or a MACHINE-BORN flag that lands parked at the operator's gate.

  Bands (config per-instance, defaults below):
    * a gate parked longer than `gate_stale_ms` → a reminder post (once per `renag_ms`)
    * a non-merged workline with no stage advance for `stalled_ms` → `Workline.flag/2`
      (once per slug; `maint-*` flags never flag themselves)

  Single-node by declaration: the always-up service runs ONE instance (`FUNES_MAINTAIN=1`),
  so no cross-instance claim dance — revisit with `UPDATE … RETURNING` if that ever changes.
  """

  use GenServer

  import Ecto.Query

  alias Funes.Channel
  alias Funes.Event
  alias Funes.Repo
  alias Funes.Thread
  alias Funes.Workline

  @defaults [
    sweep_interval_ms: to_timeout(minute: 30),
    gate_stale_ms: to_timeout(day: 1),
    stalled_ms: to_timeout(day: 3),
    renag_ms: to_timeout(day: 1)
  ]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    if name, do: GenServer.start_link(__MODULE__, opts, name: name), else: GenServer.start_link(__MODULE__, opts)
  end

  @doc "Synchronize with the monitor — returns after every queued sweep has run (tests)."
  def drain(server), do: GenServer.call(server, :drain)

  @impl true
  def init(opts) do
    opts = Keyword.merge(@defaults, opts)
    Process.send_after(self(), :sweep, opts[:sweep_interval_ms])
    {:ok, %{opts: opts, nagged: %{}}}
  end

  @impl true
  def handle_call(:drain, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info(:sweep, %{opts: opts} = state) do
    Process.send_after(self(), :sweep, opts[:sweep_interval_ms])
    {:noreply, state |> sweep_gates() |> sweep_stalled()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp sweep_gates(%{opts: opts, nagged: nagged} = state) do
    now = System.monotonic_time(:millisecond)

    nagged =
      for thread <- parked_gates(), stale?(thread, opts[:gate_stale_ms]), reduce: nagged do
        acc ->
          last = Map.get(acc, thread.id, 0)

          if last == 0 or now - last >= opts[:renag_ms] do
            post(thread, "⏸ workline #{thread.slug} still parked at #{thread.stage} — approve #{thread.id}")
            Map.put(acc, thread.id, now)
          else
            acc
          end
      end

    %{state | nagged: nagged}
  end

  defp sweep_stalled(%{opts: opts} = state) do
    for thread <- stalled_candidates(),
        stale?(thread, opts[:stalled_ms]),
        not String.starts_with?(thread.slug, "maint-"),
        is_nil(Repo.get_by(Thread, slug: "maint-#{thread.slug}")) do
      Workline.flag(
        %{title: "maintain: #{thread.slug} stalled at #{thread.stage}", slug: "maint-#{thread.slug}"},
        "breach: workline #{thread.slug} (##{thread.id}) has not advanced past #{thread.stage} " <>
          "within the control band — decide: push it, restaff it, or delete it."
      )
    end

    state
  end

  defp parked_gates do
    Repo.all(from t in Thread, where: t.state == "open" and not is_nil(t.awaiting))
  end

  defp stalled_candidates do
    Repo.all(
      from t in Thread,
        where: t.state == "open" and not is_nil(t.stage) and t.stage != "merged" and is_nil(t.awaiting)
    )
  end

  # Age from the LAST stage advance (or open) — the band is about progress, not existence.
  defp stale?(thread, band_ms) do
    last =
      Repo.one(
        from e in Event,
          where: e.thread_id == ^thread.id and e.kind == "stage_advanced",
          order_by: [desc: e.id],
          limit: 1,
          select: e.created_at
      ) || thread.created_at

    DateTime.diff(DateTime.utc_now(), last, :millisecond) >= band_ms
  end

  defp post(thread, body) do
    Channel.post(%{thread_id: thread.id, author: "funes", body: body})
    :ok
  rescue
    _ -> :ok
  end
end
