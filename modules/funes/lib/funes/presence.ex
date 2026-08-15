defmodule Funes.Presence do
  @moduledoc """
  Warmth — presence's concrete half (aleph §3b), in one home so the switchboard and
  the roster share one definition instead of drifting. A session is **warm** (cheap
  to resume) only while its context is still in the prompt cache (~1h,
  `:warmth_window_seconds`); past that it is **cold** and must not be woken, or a
  poke pays a full transcript re-ingestion. The switchboard won't wake a cold
  session; the IN FLIGHT roster shows who is on the clock. The engine-credit half of
  "clocked out" (spent credits / rate-limit window) is a separate, deferred signal.
  """
  @default_warmth_seconds 3600

  @doc "The configured warmth window in seconds."
  def warmth_window,
    do: Application.get_env(:funes, :warmth_window_seconds, @default_warmth_seconds)

  @doc "The instant before which a `last_active_at` is cold. Pass `now` for testable time."
  def warmth_cutoff(now \\ now()), do: DateTime.add(now, -warmth_window(), :second)

  @doc "Is a session (or a bare `last_active_at`) warm as of `now`?"
  def warm?(session_or_time, now \\ now())
  def warm?(%{last_active_at: at}, now), do: warm?(at, now)
  def warm?(nil, _now), do: false
  def warm?(%DateTime{} = at, now), do: DateTime.compare(at, warmth_cutoff(now)) == :gt

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
