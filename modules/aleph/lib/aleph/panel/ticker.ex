defmodule Aleph.Panel.Ticker do
  @moduledoc """
  The bottom band framing the Tlön center: a one-line, always-visible pulse of the LATEST funes
  activity event, directly under the terminal (`Aleph.Panel.Activity` is the full newest-first
  feed in the right sidebar; this is the footer-style summary). Shares `Activity.summarize/1` so
  the pulse and the feed never drift on how an event reads.

  Data is `%{events: [{tag, row}, ...]}`, newest-first (the Cockpit's activity buffer — same
  shape Activity renders from).
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2]

  alias Aleph.Panel.Activity

  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{events: [latest | _]}, rect) do
    {icon, style, text} = Activity.summarize(latest)
    Aleph.Panel.clip([[{"funes  ", :header}, {icon, style}, {text, style}]], rect)
  end

  def render(_data, rect), do: Aleph.Panel.clip([line("funes · idle", :dim)], rect)
end
