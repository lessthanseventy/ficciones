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
  The injection turns for a posted message: one per mentioned coworker EXCEPT the author's own
  window (never echo a post back to its sender — that's the loop guard). Each is
  `{window_name, text}`; the text is one line (newlines flattened) and carries the thread id so the
  woken coworker can reply on the right thread even when its funes MCP isn't wired.
  """
  @spec route(map()) :: [{String.t(), String.t()}]
  def route(%{author: author, body: body, thread_id: tid}) do
    author_window = coworkers()[author]
    one_line = String.replace(body || "", "\n", " ")
    tid_str = if tid, do: "##{tid}", else: "?"

    for {_handle, window} <- mentions(body), window != author_window do
      {window, "[funes thread #{tid_str}] #{display_author(author)}: #{one_line}"}
    end
  end

  def route(_), do: []

  # The sender label on the injected turn — the real handle, or "someone" under TLON_MENTION_LABEL=anon.
  defp display_author(author) do
    case System.get_env("TLON_MENTION_LABEL") do
      "anon" -> "someone"
      _ -> author
    end
  end
end
