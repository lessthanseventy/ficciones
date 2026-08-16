defmodule Aleph.Panel.Session do
  @moduledoc """
  SESSION — the center 50%: a live view of the focused thread's **tmux** pane (design §2/§4).
  tmux stays the multiplexer; aleph only renders a view of it. The Cockpit captures the pane
  (`Aleph.Tmux.capture/2`) and passes the lines here; when focused, keystrokes are forwarded to
  the pane via `send-keys`. No pane yet → an honest placeholder, never invented content.

  Data is `%{target: pane_ref | nil, lines: [String.t()] | nil, focused?: boolean}`.
  """
  @behaviour Aleph.Panel

  import Aleph.Panel, only: [line: 2, blank: 0]

  # No Bus topic: the pane's liveness is asked of tmux live (§5), never mirrored on the Bus.
  @impl Aleph.Panel
  def topics(_assigns), do: []

  @impl Aleph.Panel
  def render(%{lines: lines} = data, rect) when is_list(lines) do
    hint =
      if data[:focused?],
        do: {" — keys go here · Esc to release", :warm},
        else: {" — Enter to focus", :dim}

    body = Enum.map(lines, &line(&1, :normal))
    Aleph.Panel.clip([[{"SESSION", :header}, hint], blank() | body], rect)
  end

  def render(_no_session, rect) do
    Aleph.Panel.clip(
      [
        line("SESSION", :header),
        blank(),
        line("no live tmux session for this thread", :dim),
        blank(),
        line("start one in a tmux pane, then set the", :dim),
        line("session's pane_ref to that pane's target", :dim)
      ],
      rect
    )
  end
end
