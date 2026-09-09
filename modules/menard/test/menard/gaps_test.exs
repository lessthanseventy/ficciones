defmodule Menard.AttrTest do
  # Module attributes — the tables a module keeps at the top, which no clause verb reaches.
  use ExUnit.Case, async: true

  alias Menard.Attr

  @src """
  defmodule A do
    @moduledoc "docs"

    @kinds [:a, :b]

    @hints [
      {"x", "one"},
      {"y", "two"}
    ]

    @doc "first"
    def go(:a), do: 1

    @doc "second"
    def go(:b), do: 2
  end
  """

  test "get reads the value exactly as written, single line or block" do
    assert Attr.get(@src, "kinds") == "[:a, :b]"
    assert Attr.get(@src, :hints) =~ ~s({"x", "one"})
  end

  test "a leading @ on the name is accepted — it is how the attribute is written" do
    assert Attr.get(@src, "@kinds") == "[:a, :b]"
  end

  test "set replaces the value and leaves everything else alone" do
    out = Attr.set(@src, "kinds", "[:a, :b, :c]")

    assert out =~ "@kinds [:a, :b, :c]"
    assert out =~ ~s(@moduledoc "docs")
    assert out =~ "def go(:a), do: 1"
  end

  test "set over a MULTI-LINE value replaces the whole block, not just its first line" do
    out = Attr.set(@src, "hints", "[{\"z\", \"only\"}]")

    assert out =~ ~s(@hints [{"z", "only"}])
    refute out =~ ~s({"x", "one"})
    refute out =~ ~s({"y", "two"})
    assert out =~ "@doc \"first\""
  end

  test "a multi-line value lands as a block at the attribute's own column" do
    out = Attr.set(@src, "kinds", "[\n  :a,\n  :z\n]")

    assert out =~ "  @kinds [\n    :a,\n    :z\n  ]"
  end

  test "setting one that is missing adds it above the first definition, where tables live" do
    out = Attr.set(@src, "timeout", "5_000")

    assert out =~ "@timeout 5_000"
    # above the first def, not appended after the last
    assert String.split(out, "@timeout") |> hd() |> String.contains?("def go") == false
  end

  test "delete removes the whole attribute, block and all" do
    out = Attr.delete(@src, "hints")

    refute out =~ "@hints"
    refute out =~ ~s({"x", "one"})
    assert out =~ "@kinds [:a, :b]"
  end

  test "a name that repeats per clause is refused, with its lines, not guessed at" do
    assert {:error, message} = Attr.get(@src, "doc")
    assert message =~ "set 2 times"
    assert message =~ "clause verbs"
  end

  test "an attribute that isn't there reads as missing" do
    assert Attr.get(@src, "nope") == {:error, :missing}
  end

  test "list names what the module sets, with lines" do
    names = @src |> Attr.list() |> Enum.map(&elem(&1, 0))
    assert :kinds in names
    assert :hints in names
  end
end

defmodule Menard.BlockTest do
  # A macro's do-block: schema do, describe "…" do, test "…" do.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule A do
    schema do
      field(:x, :string)
      field(:y, :integer)
    end

    describe "one" do
      test "a" do
        assert 1 == 1
      end
    end

    describe "two" do
      test "b" do
        assert 2 == 2
      end
    end
  end
  """

  test "replace swaps a block's body, keeping the header line and the end" do
    out = Block.replace(@src, "schema", "field(:only, :string)")

    assert out =~ "schema do\n    field(:only, :string)\n  end"
    refute out =~ "field(:y, :integer)"
    assert out =~ ~s(describe "one" do)
  end

  test "get reads a block's body as written" do
    assert Block.get(@src, "schema") =~ "field(:x, :string)"
  end

  test "a label addresses one of several blocks sharing a name" do
    out = Block.replace(@src, "describe", "test \"c\" do\n  assert 3 == 3\nend", label: "two")

    assert out =~ ~s(describe "two" do\n    test "c" do)
    assert out =~ ~s(test "a" do)
  end

  test "several blocks of one name with no label is refused, listing them" do
    assert {:error, message} = Block.replace(@src, "describe", "x")
    assert message =~ "2 `describe` blocks"
    assert message =~ ~s("one")
    assert message =~ ~s("two")
  end

  test "a block that isn't there is an error, not a silent no-op" do
    assert {:error, message} = Block.get(@src, "nope")
    assert message =~ "no `nope do` block"
  end

  test "list finds nested blocks too — a test lives inside a describe" do
    found = Block.list(@src)

    assert {:schema, nil, _line} = Enum.find(found, &(elem(&1, 0) == :schema))
    assert Enum.any?(found, &match?({:test, "a", _}, &1))
  end

  test "def and defmodule are not blocks — they have their own verbs" do
    names = @src |> Block.list() |> Enum.map(&elem(&1, 0))
    refute :defmodule in names
    refute :def in names
  end
end

defmodule Menard.ModuleTest do
  # Whole modules inside a file — the multi-module shape the MCP tool components use.
  use ExUnit.Case, async: true

  @src """
  defmodule A do
    def a, do: 1
  end

  defmodule B do
    def b, do: 2
  end
  """

  test "add appends a module after the last one" do
    out = Menard.Module.add(@src, "defmodule C do\n  def c, do: 3\nend")

    assert out =~ "defmodule B do\n  def b, do: 2\nend\n\ndefmodule C do"
    assert String.ends_with?(out, "end\n")
  end

  test "a name the file already defines is refused" do
    assert {:error, message} = Menard.Module.add(@src, "defmodule B do\nend")
    assert message =~ "already defined"
  end

  test "anything that is not a whole module is refused" do
    assert {:error, message} = Menard.Module.add(@src, "def loose, do: 1")
    assert message =~ "whole `defmodule"
  end

  test "list names the modules in source order" do
    assert Menard.Module.list(@src) == ["A", "B"]
  end
end

defmodule Menard.DepsTest do
  # What a function references — the read that answers "can this move?".
  use ExUnit.Case, async: true

  alias Menard.Deps

  @src """
  defmodule A do
    alias App.Cat

    @timeout 5_000

    def go(x) do
      shared(x) + only_mine(x) + Sourceror.get_range(x) + Cat.purr()
    end

    def other(x), do: shared(x) + @timeout

    defp shared(x), do: x
    defp only_mine(x), do: x
  end
  """

  test "a local helper nothing else calls is free to move" do
    report = Deps.of(@src, "go/1")
    assert %{call: "only_mine/1", shared_with: []} = Enum.find(report.locals, &(&1.call == "only_mine/1"))
  end

  test "a local helper another function shares CANNOT move, and it names who else needs it" do
    report = Deps.of(@src, "go/1")
    assert %{call: "shared/1", shared_with: ["other/1"]} = Enum.find(report.locals, &(&1.call == "shared/1"))
  end

  test "reports the remote calls and the modules whose aliases must travel" do
    report = Deps.of(@src, "go/1")

    assert "Sourceror.get_range/1" in report.remotes
    assert "Cat" in report.modules
    assert "Sourceror" in report.modules
  end

  test "reports the attributes it reads — those do NOT travel with the code" do
    assert Deps.of(@src, "other/1").attributes == [:timeout]
    assert Deps.of(@src, "go/1").attributes == []
  end

  test "Kernel and the special forms are not reported as local calls" do
    calls = Enum.map(Deps.of(@src, "go/1").locals, & &1.call)

    refute "+/2" in calls
    assert "shared/1" in calls
  end

  test "a function that isn't there is an error naming what is" do
    assert {:error, message} = Deps.of(@src, "nope/9")
    assert message =~ "go/1"
  end
end
