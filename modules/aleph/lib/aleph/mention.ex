defmodule Aleph.Mention do
  @moduledoc """
  @-mention routing — the Tlön coworkers share one thread and address each other by name. A funes
  message that `@`-names a coworker wakes it by arriving as a turn in its tmux window (the Cockpit
  does the `tmux send-keys`; this module only DECIDES who to wake and what to say). Pure, so it tests
  without a TTY or a live tmux.

  The handle → window mapping (`@base_coworkers`) is the one piece of structural knowledge here — it
  must match the window names the Cockpit's spawn code creates (`tertius`, `hronir`).

  ## Experiment knobs (env, off by default — see docs/tlon-experiments)

    * `TLON_THIRD_AGENT="<handle>:<window>"` adds a third coworker (the cockpit spawns its window and
      it joins the wake-loop) — for breaking the two-body agree/disagree dynamic.
    * `TLON_MENTION_LABEL=anon` labels the injected turn's sender as "someone" instead of its handle,
      for the "does the argument survive without the personas" run. NOTE: funes still records the
      true author, so pair it with a prompt telling them to answer the injected turn, not re-read the
      thread.
  """

  alias Aleph.Crew

  # funes handle → the tmux window (tab) the coworker runs in. Keep in sync with the spawn code.
  # tertius-machine (the meta agent) is the center; claude-machine is the builder, tab `hronir`.
  @base_coworkers %{"claude-machine" => "hronir", "tertius-machine" => "tertius"}

  @doc "The optional third experiment coworker from `$TLON_THIRD_AGENT` (\"handle:window\"), or nil."
  @spec third_agent() :: %{author: String.t(), window: String.t()} | nil
  def third_agent do
    with val when is_binary(val) <- System.get_env("TLON_THIRD_AGENT"),
         [author, window] <- String.split(String.trim(val), ":", parts: 2),
         true <- author != "" and window != "" do
      %{author: author, window: window}
    else
      _ -> nil
    end
  end

  @doc "The active handle → window map: the tertius/hronir base, plus `$TLON_THIRD_AGENT` if set."
  @spec coworkers() :: %{String.t() => String.t()}
  def coworkers do
    case third_agent() do
      %{author: a, window: w} -> Map.put(@base_coworkers, a, w)
      nil -> @base_coworkers
    end
  end

  @doc "The {handle, window} pairs @-mentioned in `body` (deduped, first-seen order)."
  @spec mentions(String.t() | nil) :: [{String.t(), String.t()}]
  def mentions(nil), do: []

  def mentions(body) do
    cw = coworkers()

    ~r/@([\w-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(fn handle ->
      case Map.get(cw, handle) do
        nil -> []
        window -> [{handle, window}]
      end
    end)
  end

  @doc """
  The injection turns for a posted message. With an explicit coworker `@`-mention, wakes each
  mentioned coworker (except the author's own window — the loop guard). With NO coworker mention,
  falls back to `opts[:lead]` — the thread's staffed lead coworker — so a bare operator reply
  still reaches someone. Each turn is `{window_name, one_line_text}`.

  `opts[:staffed_window]` (e.g. `"t9"`) redirects the lead onto its OWN per-thread window: on a
  staffed thread the lead coworker runs in a `t<id>` window, not the standing handle→window
  slot, so any target that resolves to the lead's standing window is rewritten onto it. Without it,
  a staffed thread's turns would wake the STANDING coworker instead of the session working THAT
  thread. The author-exclusion loop guard runs before the redirect (an agent's own post — its
  standing window — is dropped first), so the thread's own session never wakes itself.
  """
  @spec route(map(), keyword()) :: [{String.t(), String.t()}]
  def route(row, opts \\ [])

  def route(%{author: author, body: body, thread_id: tid}, opts) do
    author_window = resolve(author, tid)
    targets = mention_targets(body, opts[:lead], tid)
    lead_window = opts[:lead] && resolve(opts[:lead], tid)
    staffed = opts[:staffed_window]

    for_result =
      for window <- targets, window != author_window do
        {redirect(window, lead_window, staffed),
         "[funes thread #{tid_str(tid)}] #{display_author(author)}: #{one_line(body)}"}
      end

    Enum.uniq(for_result)
  end

  def route(_, _), do: []

  # A handle → window: the static base map, else a crew role's per-thread window (`r<tid>`), else
  # nil. Crew roles only resolve WITH a thread id — their window is per-thread, so a nil tid
  # (standing thread, uqbar console) leaves a crew handle unresolved and it is simply not woken.
  defp resolve(handle, tid) do
    cond do
      w = coworkers()[handle] -> w
      role = tid && Crew.handle_role(handle) -> Crew.crew_window(role, tid)
      true -> nil
    end
  end

  # On a staffed thread the lead lives in its own `t<id>` window: rewrite any target that resolves
  # to the lead's standing window onto it. nil staffed_window (standing thread / no per-thread
  # session) = no redirect, the old handle→window target stands.
  defp redirect(window, lead_window, staffed) when is_binary(staffed) and window == lead_window, do: staffed
  defp redirect(window, _lead_window, _staffed), do: window

  # The windows to wake: the @-mentioned handles resolved for THIS thread, or — when none are
  # named — the thread's lead coworker's window (nil/unknown → []).
  defp mention_targets(body, lead, tid) do
    case mentioned_handles(body) do
      [] -> lead |> lead_window(tid) |> List.wrap()
      handles -> handles |> Enum.map(&resolve(&1, tid)) |> Enum.reject(&is_nil/1)
    end
  end

  defp lead_window(nil, _tid), do: nil
  defp lead_window(handle, tid), do: resolve(handle, tid)

  # Every @handle token in the body (deduped, first-seen). Resolution to windows happens per-thread
  # in `resolve/2`; this stays purely lexical so crew handles are seen even though they are not in
  # the static `coworkers/0` map.
  defp mentioned_handles(body) do
    ~r/@([\w-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")
  defp tid_str(nil), do: "?"
  defp tid_str(tid), do: "##{tid}"

  # The sender label on the injected turn — the real handle, or "someone" under TLON_MENTION_LABEL=anon.
  defp display_author(author) do
    case System.get_env("TLON_MENTION_LABEL") do
      "anon" -> "someone"
      _ -> author
    end
  end
end
