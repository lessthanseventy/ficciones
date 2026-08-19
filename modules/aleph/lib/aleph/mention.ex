defmodule Aleph.Mention do
  @moduledoc """
  @-mention routing — the point of the cockpit: pi and claude share one thread, and either can
  address the other by name. A funes message that `@`-names a Tlön coworker wakes that coworker by
  arriving as a turn in its tmux window (the Cockpit does the `tmux send-keys`; this module only
  DECIDES who to wake and what to say). Pure, so it tests without a TTY or a live tmux.

  The mapping from a coworker's funes handle (its `FUNES_AUTHOR`) to its tmux window name is the
  one piece of structural knowledge here — it must match the window names `spawn_machine_coworker`
  (`pi`) and `spawn_claude_coworker` (`claude`) create.

  ## Experiment knobs (env, off by default — see docs/tlon-experiments)

    * `TLON_THIRD_AGENT="<handle>:<window>"` adds a third coworker (the cockpit spawns its window and
      it joins the wake-loop) — for breaking the two-body agree/disagree dynamic.
    * `TLON_MENTION_LABEL=anon` labels the injected turn's sender as "someone" instead of its handle,
      for the "does the argument survive without the personas" run. NOTE: funes still records the
      true author, so pair it with a prompt telling them to answer the injected turn, not re-read the
      thread.
  """

  # funes handle → the tmux window name the coworker runs in. Keep in sync with the spawn code.
  @base_coworkers %{"pi-machine" => "pi", "claude-machine" => "claude"}

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

  @doc "The active handle → window map: the pi/claude base, plus `$TLON_THIRD_AGENT` if set."
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
  """
  @spec route(map(), keyword()) :: [{String.t(), String.t()}]
  def route(row, opts \\ [])

  def route(%{author: author, body: body, thread_id: tid}, opts) do
    author_window = coworkers()[author]
    targets = mention_targets(body, opts[:lead])

    for_result =
      for window <- targets, window != author_window do
        {window, "[funes thread #{tid_str(tid)}] #{display_author(author)}: #{one_line(body)}"}
      end

    Enum.uniq(for_result)
  end

  def route(_, _), do: []

  # The windows to wake: the explicitly @-mentioned coworkers, or — when none are named — the
  # thread's lead coworker's window (nil / unknown lead → []).
  defp mention_targets(body, lead) do
    case mentions(body) do
      [] -> lead |> lead_window() |> List.wrap()
      ms -> Enum.map(ms, fn {_handle, window} -> window end)
    end
  end

  defp lead_window(nil), do: nil
  defp lead_window(handle), do: coworkers()[handle]

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
