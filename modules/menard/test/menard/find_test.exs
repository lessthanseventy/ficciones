defmodule Menard.FindTest do
  # The search verb: what grep is for code that knows what a call, a def, or an alias is.
  # Every hit is `{file, line, column, kind, text}` — data, not a coloured line.
  use ExUnit.Case, async: true

  alias Menard.Find

  @src """
  defmodule Demo do
    alias Server.Channels
    # Channels.general in a comment does not count
    def home(ws), do: Channels.general(ws.id)
    def other(ws), do: Server.Channels.general(ws.id)
    defp general(x), do: x
    def go, do: general(1) <> "Channels.general(2)"
  end
  """

  test "calls: a remote call by Mod.fun, aliased or fully qualified, not strings or comments" do
    hits = Find.calls(@src, "Server.Channels.general")
    assert Enum.map(hits, & &1.line) == [4, 5]
    assert Enum.all?(hits, &(&1.kind == :call))
    assert hd(hits).text =~ "Channels.general(ws.id)"
  end

  test "calls: a local call by bare name" do
    assert [%{line: 7}] = Find.calls(@src, "general")
  end

  test "defs: by name, any arity or a given one" do
    assert [%{line: 6, kind: :defp, text: "defp general(x)"}] = Find.defs(@src, "general")
    assert [] = Find.defs(@src, "general/2")
    assert [%{line: 4}] = Find.defs(@src, "home/1")
  end

  test "aliases: where a module is aliased" do
    assert [%{line: 2, kind: :alias}] = Find.aliases(@src, "Server.Channels")
  end
end
