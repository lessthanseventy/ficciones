defmodule Funes.TestDB do
  @moduledoc """
  FK-safe truncation for the shared test database. The suite runs against one DB
  with no sandbox, so each test clears the domain rows first — and the order is
  load-bearing: children before parents, or a `delete_all` trips a foreign key. One
  helper so a new suite (or a reordering of them) can't reintroduce the ordering bug
  a review caught, where cleanups deleted `thread` while `fact`/`event`/`issue` still
  referenced it and only passed because the suite that made those rows ran last.
  """
  alias Funes.Repo

  # fact → thread+session, event/issue/message → thread, session → agent+thread,
  # thread → agent. So: the leaf rows, then message/session, then thread, then agent.
  @ordered [
    Funes.Fact,
    Funes.Event,
    Funes.Issue,
    Funes.Message,
    Funes.Session,
    Funes.Thread,
    Funes.Agent
  ]

  @doc "Delete every domain row, children before parents."
  def clean! do
    Enum.each(@ordered, &Repo.delete_all/1)
  end
end
