defmodule Aleph.Mention do
  @moduledoc """
  @-mention routing — the point of the cockpit: pi and claude share one thread, and either can
  address the other by name. A funes message that `@`-names a Tlön coworker wakes that coworker by
  arriving as a turn in its tmux window (the Cockpit does the `tmux send-keys`; this module only
  DECIDES who to wake and what to say). Pure, so it tests without a TTY or a live tmux.

  The mapping from a coworker's funes handle (its `FUNES_AUTHOR`) to its tmux window name is the
  one piece of structural knowledge here — it must match the window names `spawn_machine_coworker`
  (`pi`) and `spawn_claude_coworker` (`claude`) create.
  """

  # funes handle → the tmux window name the coworker runs in. Keep in sync with the spawn code.
  @coworkers %{"pi-machine" => "pi", "claude-machine" => "claude"}

  @doc "The {handle, window} pairs @-mentioned in `body` (deduped, first-seen order)."
  @spec mentions(String.t() | nil) :: [{String.t(), String.t()}]
  def mentions(nil), do: []

  def mentions(body) do
    ~r/@([\w-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(fn handle ->
      case Map.get(@coworkers, handle) do
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
    author_window = @coworkers[author]
    one_line = String.replace(body || "", "\n", " ")
    tid_str = if tid, do: "##{tid}", else: "?"

    for {_handle, window} <- mentions(body), window != author_window do
      {window, "[funes thread #{tid_str}] #{author}: #{one_line}"}
    end
  end

  def route(_), do: []
end
