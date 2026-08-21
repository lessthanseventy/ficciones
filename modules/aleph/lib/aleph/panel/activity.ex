defmodule Aleph.Panel.Activity do
  @moduledoc """
  The machine-wide funes activity feed (Tlön right sidebar): every durable write — a fact
  banked, a check passed/failed, work landed, a message posted, an issue/question raised —
  as one colored, newest-first stream (design: replace the opaque "funes · calling funes (2
  tools)" with real visibility). Fed by `Funes.Bus`'s global `activity` topic (cross-thread,
  unlike `Chorus`'s per-thread blocks); the Cockpit keeps the bounded buffer, this panel is a
  pure render over it.

  Data is `%{events: [{tag, row}, ...]}`, newest-first (the Cockpit's buffer order).
  `summarize/1` — the `{tag, row} -> {icon, style, text}` mapping — is exported so the footer
  pulse (status bar) reuses it verbatim rather than re-deriving it (no panel/footer drift).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  # The cockpit subscribes to the activity topic once (Bus.subscribe_activity), globally — no
  # per-assigns topic needed here (mirrors Chorus, which does the same for messages).
  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{events: events}, rect) do
    header = [line("funes · activity", :header), blank()]

    body =
      case events do
        [] -> [line("no activity yet", :dim)]
        evs -> Enum.map(evs, &event_row/1)
      end

    Aleph.Panel.clip(header ++ body, rect)
  end

  defp event_row(event) do
    {icon, style, text} = summarize(event)
    [{icon, style}, {text, style}]
  end

  @doc """
  Map one buffered `{tag, row}` Bus event to `{icon, style, summary text}` — the single source
  both this panel and the footer pulse render from.
  """
  @spec summarize({atom(), map()}) :: {String.t(), atom(), String.t()}
  def summarize({:fact_banked, fact}), do: {"● ", :event_ok, "fact ##{fact.id} #{fact.kind} — #{fact.text}"}

  def summarize({:event_recorded, %{kind: "check_passed"} = ev}), do: {"✓ ", :event_ok, check_text(ev)}
  def summarize({:event_recorded, %{kind: "check_failed"} = ev}), do: {"✗ ", :event_bad, check_text(ev)}
  def summarize({:event_recorded, %{kind: "work_landed"} = ev}), do: {"⚑ ", :event_done, work_text(ev)}
  def summarize({:event_recorded, ev}), do: {"· ", :event_msg, ev.kind}

  def summarize({:message_posted, m}), do: {"▸ ", :event_msg, "#{m.author}: #{m.body}"}

  def summarize({:issue_raised, row}), do: {"◆ ", :event_warn, "issue: #{row.summary}"}
  def summarize({:question_raised, row}), do: {"◆ ", :event_warn, "question: #{row.text}"}

  # Anything else that rides the activity topic (issue_resolved, question_resolved, todo_*…) —
  # a plain row rather than a silent drop, so the feed never hides a real write.
  def summarize({tag, _row}), do: {"· ", :event_msg, to_string(tag)}

  defp check_text(%{detail: detail}) do
    d = detail || %{}
    cmd = d["cmd"] || "check"
    if d["exit"], do: "#{cmd} — exit #{d["exit"]}", else: cmd
  end

  defp work_text(%{detail: detail}) do
    d = detail || %{}
    d["summary"] || "work landed"
  end
end
