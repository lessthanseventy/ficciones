defmodule Aleph.ArbiterTest do
  @moduledoc "The aleph hub's arbiter backend — funes' wake actuated against embedded terminals."
  use ExUnit.Case, async: false

  alias Aleph.Arbiter
  alias Aleph.Sessions
  alias Aleph.Terminal

  test "sanitize collapses a prompt to one clean line" do
    assert Arbiter.sanitize("first\nsecond\ttab   run") == "first second tab run"
  end

  test "thread_id parses FUNES_THREAD from an exports block, else nil" do
    assert Arbiter.thread_id(~s(export FUNES_MCP_URL="x"\nexport FUNES_THREAD="42")) == 42
    assert Arbiter.thread_id("no thread here") == nil
  end

  test "wake with no live terminal for the thread is {:error, :no_terminal}, never a crash" do
    assert Arbiter.wake(%{thread_id: 999_999}, "hi") == {:error, :no_terminal}
  end

  test "wake writes the sanitized prompt + Enter into the thread's terminal" do
    # cat echoes stdin, so a wake that reaches the PTY reappears on the screen.
    {:ok, term} = Sessions.ensure(8801, cmd: "/bin/cat", cols: 40, rows: 4)
    on_exit(fn -> if Process.alive?(term), do: GenServer.stop(term) end)

    assert :ok = Arbiter.wake(%{thread_id: 8801}, "wake up")
    Process.sleep(120)

    text = term |> Terminal.cells() |> List.flatten() |> Enum.map_join(fn {g, _, _, _} -> g end)
    assert text =~ "wake up"
  end
end
