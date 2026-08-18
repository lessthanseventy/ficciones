defmodule Mix.Tasks.Aleph.MachineLog do
  @shortdoc "Tail the Tlön machine-thread conversation as a clean transcript (a tmux tab)"
  @moduledoc """
  A clean, scannable read-out of the Tlön machine thread — the pi↔claude (and any third-voice)
  conversation — as a Slack-style transcript, so the actual harness windows (`pi`, `claude`) can
  stay their messy selves. aleph opens this as the `chat` window (the third Tlön tab); run it by
  hand from `modules/aleph` for the same log in any terminal.

  Each message renders as a coloured `author  HH:MM` header (every handle gets its OWN stable
  colour, so the eye tracks a speaker down the column) with the body wrapped and indented beneath.

  ## Why it POLLS the db instead of subscribing to the Bus

  This is a SEPARATE OS process from the cockpit, and `Funes.Bus` is `Phoenix.PubSub` — node-local.
  A subscription here would never see the cockpit's broadcasts. So it reads the one thing the two
  processes DO share: the SQLite file at `FUNES_DB` (carried into the Tlön tmux session env), polling
  `Funes.Channel.machine_thread/0` for messages past the last id it printed. That is funes' own
  "a read model is a query over the durable db" law — the logbook works the same way.
  """
  use Mix.Task
  use Boundary, classify_to: Aleph

  alias Funes.Channel

  @requirements ["app.config"]

  # Poll cadence for new messages. Fast enough to feel live in a conversation, cheap enough that a
  # WAL reader against a quiet db is free.
  @poll_ms 700

  # Column width fallback when stdout isn't a tty (`:io.columns` fails) — recomputed every render
  # otherwise, so the transcript reflows when the tmux pane resizes.
  @fallback_cols 80

  @reset "\e[0m"
  @dim "\e[2m"

  # A spread of 256-colour foregrounds with enough hue/lightness distance to stay distinct on the
  # dark cockpit background. Known handles get a hand-picked slot; everyone else is hashed onto the
  # palette (stable per handle, so a speaker keeps one colour for the whole session).
  @palette [39, 213, 214, 84, 209, 141, 45, 220, 205, 156, 111, 173]
  @known %{"pi-machine" => 213, "claude-machine" => 45, "andrew" => 220}

  @impl Mix.Task
  def run(_args) do
    # READER role: no MCP, no switchboard. The cockpit already binds :4041; a second bind here would
    # crash the tab on boot. Override before the app starts so `Funes.Application` reads the false.
    Application.put_env(:funes, :start_mcp, false)
    Application.put_env(:funes, :start_switchboard, false)

    # This is a HUMAN-facing transcript, not a service log: silence Ecto's per-query `[debug] QUERY`
    # lines (they'd spew into the tab every poll) and funes' boot chatter. `Repo log: false` kills the
    # query logs outright; the level bump hides everything below a warning we'd actually want to see.
    Application.put_env(:funes, Funes.Repo, Keyword.put(Application.get_env(:funes, Funes.Repo, []), :log, false))
    Logger.configure(level: :warning)

    case Application.ensure_all_started(:funes) do
      {:ok, _apps} ->
        IO.write(banner())
        loop(%{thread_id: nil, last_id: 0})

      {:error, reason} ->
        Mix.shell().error("aleph.machine_log could not boot funes: #{inspect(reason)}")
    end
  end

  # The follow loop: re-read the latest machine thread each tick (it can rotate — a new machine
  # thread supersedes the old), print whatever is new, sleep. Never returns.
  defp loop(state) do
    state
    |> tick()
    |> then(fn next ->
      Process.sleep(@poll_ms)
      loop(next)
    end)
  end

  defp tick(state) do
    case Channel.machine_thread() do
      nil ->
        state

      %{id: id} = thread ->
        state = maybe_thread_switch(state, id)
        emit_new(thread, state)
    end
  end

  # A rotated machine thread (or the very first one) resets the id cursor; an actual rotation also
  # prints a divider so the transcript shows where one thread ended and the next began.
  defp maybe_thread_switch(%{thread_id: same} = state, same), do: state

  defp maybe_thread_switch(%{thread_id: nil} = state, id), do: %{state | thread_id: id, last_id: 0}

  defp maybe_thread_switch(state, id) do
    IO.write("\n#{@dim}── new machine thread ──#{@reset}\n\n")
    %{state | thread_id: id, last_id: 0}
  end

  # Print every message past the cursor (id-ordered = post order under funes' single writer), then
  # advance the cursor to the last one shown.
  defp emit_new(thread, state) do
    fresh = thread |> Channel.thread_messages() |> Enum.filter(&(&1.id > state.last_id))

    case fresh do
      [] ->
        state

      messages ->
        cols = columns()
        Enum.each(messages, &IO.write(render(&1, cols)))
        %{state | last_id: List.last(messages).id}
    end
  end

  # One message: a coloured `author  HH:MM` header, then the body wrapped to the column and indented
  # two spaces so the author names form a scannable left edge. Blank line after, chat-log style.
  defp render(%{author: author, body: body, created_at: at}, cols) do
    color = color_for(author)
    header = "#{color}#{author}#{@reset}  #{@dim}#{time(at)}#{@reset}\n"
    header <> body_block(body, cols) <> "\n"
  end

  # Wrap each source line to the column (preserving the author's own paragraph breaks) with a
  # hanging two-space indent. An empty body still yields nothing but the header.
  defp body_block(body, cols) do
    width = max(cols - 2, 1)

    (body || "")
    |> String.split("\n")
    |> Enum.flat_map(&Aleph.Text.wrap(&1, width))
    |> Enum.map_join("", &"  #{&1}\n")
  end

  # Stable per-handle foreground: the hand-picked slot for a known coworker, else a hash onto the
  # palette so a new/third voice still lands on its own colour and keeps it.
  defp color_for(author) do
    code = Map.get_lazy(@known, author, fn -> Enum.at(@palette, rem(:erlang.phash2(author), length(@palette))) end)
    "\e[1;38;5;#{code}m"
  end

  # HH:MM from the stored UTC timestamp (funes stores UTC; no tz db to localise against, and a
  # machine log wants consistency over wall-clock anyway).
  defp time(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M")
  defp time(_), do: "--:--"

  defp columns do
    case :io.columns() do
      {:ok, cols} -> cols
      _ -> @fallback_cols
    end
  end

  defp banner do
    "#{@dim}Tlön · machine thread — a live transcript of the coworkers' conversation." <>
      " The pi/claude tabs are the real sessions; this is just the talk.#{@reset}\n\n"
  end
end
