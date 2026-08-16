defmodule Funes.MCP.Brief do
  @moduledoc """
  JSON-safe renderings of the reads the channel serves — one renderer per row
  type, shared by the `get_dossier`/`get_facts` tools AND the resources: one
  source, two protocol doors. Every fact carries its read-time `certainty`
  (§4a: the certainty axis is a QUERY over provenance × check_cmd — `stated` >
  `checked` > `opinion`), so a brief can never launder an unchecked hunch into
  received truth (pi doc §2b). Caps keep their counts — a cut without a count
  lies.
  """

  alias Funes.Event
  alias Funes.Fact
  alias Funes.Issue
  alias Funes.Message

  @doc "A Board.in_scope/1 map, rendered."
  def scope(scope) do
    %{
      "thread_id" => scope.thread.id,
      "north_star" => scope.north_star,
      "lead" => scope.lead,
      "learnings" => capped(scope.learnings, &fact/1),
      "shipped" => capped(scope.shipped, &event/1),
      "blockers" => capped(scope.blockers, &issue/1),
      "chatter" => Enum.map(scope.chatter, &message/1)
    }
  end

  @doc "A %{shown, more} cap, rendered with its count intact."
  def capped(%{shown: shown, more: more}, render) do
    %{"shown" => Enum.map(shown, render), "more" => more}
  end

  @doc "A fact with its read-time certainty rank."
  def fact(%Fact{} = f) do
    %{
      "id" => f.id,
      "kind" => f.kind,
      "text" => f.text,
      "provenance" => f.provenance,
      "check_cmd" => f.check_cmd,
      "certainty" => certainty(f),
      "at" => at(f.created_at)
    }
  end

  @doc """
  The §4 total order, computed at read time and named in words: `stated` (the
  operator's own quoted words), `checked` (derived, carrying the command that
  re-runs it), `opinion` (derived and unverifiable — rank it last, re-verify
  before building on it).
  """
  def certainty(%Fact{provenance: "stated"}), do: "stated"
  def certainty(%Fact{check_cmd: nil}), do: "opinion"
  def certainty(%Fact{}), do: "checked"

  @doc "An event; `summary`/`evidence` surface from its human-readable detail."
  def event(%Event{} = e) do
    detail = e.detail || %{}

    %{
      "id" => e.id,
      "kind" => e.kind,
      "summary" => detail["summary"],
      "evidence" => detail["evidence"],
      "at" => at(e.created_at)
    }
  end

  @doc "An issue — the stack's tracker (pi doc §4b)."
  def issue(%Issue{} = i) do
    %{
      "id" => i.id,
      "summary" => i.summary,
      "evidence" => i.evidence,
      "found_by" => i.found_by,
      "state" => i.state,
      "at" => at(i.created_at)
    }
  end

  @doc "A message on the thread."
  def message(%Message{} = m) do
    %{
      "id" => m.id,
      "author" => m.author,
      "body" => m.body,
      "reply_to" => m.reply_to,
      "at" => at(m.created_at)
    }
  end

  defp at(nil), do: nil
  defp at(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
