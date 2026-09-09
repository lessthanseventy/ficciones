defmodule Menard.StmtTest do
  # A statement inside a body was the last thing with no verb — adding a line to a function meant
  # editing the file as text. Case arms come with it: an arm is a statement of its `case`.
  use ExUnit.Case, async: true

  alias Menard.Stmt

  @src """
  defmodule St do
    def init(_opts) do
      subscribe_a()
      subscribe_b()

      case start() do
        0 -> {:ok, :up}
        n -> {:error, n}
      end
    end

    def solo(x) do
      only_one(x)
    end
  end
  """

  test "list names the body's statements and the case arms — not `do`, the head, or a literal" do
    assert Stmt.list(@src, "init/1", "_opts") == [
             "subscribe_a()",
             "subscribe_b()",
             "case start() do\n      0 -> {:ok, :up}\n      n -> {:error, n}\n    end",
             "0 -> {:ok, :up}",
             "n -> {:error, n}"
           ]
  end

  test "a single-statement body still lists its one statement" do
    assert Stmt.list(@src, "solo/1", "x") == ["only_one(x)"]
  end

  test "insert_after puts a new statement below the one named, at its indent" do
    out = Stmt.insert_after(@src, "init/1", "_opts", "subscribe_b()", "Import.run()")

    assert out =~ "    subscribe_b()\n\n    Import.run()\n"
    assert out =~ "case start() do"
  end

  test "insert_before puts one above" do
    out = Stmt.insert_before(@src, "init/1", "_opts", "subscribe_a()", "before_all()")

    assert out =~ "    before_all()\n\n    subscribe_a()"
  end

  test "replace swaps a CASE ARM without touching its neighbour" do
    out = Stmt.replace(@src, "init/1", "_opts", "0 -> {:ok, :up}", "0 -> {:ok, :running}")

    assert out =~ "0 -> {:ok, :running}"
    assert out =~ "n -> {:error, n}"
    refute out =~ "{:ok, :up}"
  end

  test "replace swaps a plain statement" do
    out = Stmt.replace(@src, "init/1", "_opts", "subscribe_a()", "subscribe_everything()")

    assert out =~ "subscribe_everything()"
    refute out =~ "subscribe_a()"
  end

  test "delete removes the statement and the blank line it left" do
    out = Stmt.delete(@src, "init/1", "_opts", "subscribe_b()")

    refute out =~ "subscribe_b()"
    assert out =~ "subscribe_a()"
    assert out =~ "case start() do"
  end

  test "a statement that isn't there is refused, and the message lists what is" do
    assert {:error, message} = Stmt.replace(@src, "init/1", "_opts", "nope()", "x()")
    assert message =~ "no statement `nope()`"
    assert message =~ "subscribe_a()"
  end

  test "whitespace in the match doesn't matter — it is addressed as written, squashed" do
    out = Stmt.replace(@src, "init/1", "_opts", "0->{:ok,:up}", "0 -> :fine")
    assert out =~ "0 -> :fine"
  end

  test "an ambiguous match is refused with line numbers, and --nth picks one" do
    src = """
    defmodule D do
      def go(x) do
        tick()
        other(x)
        tick()
      end
    end
    """

    assert {:error, message} = Stmt.delete(src, "go/1", "x", "tick()")
    assert message =~ "2 statements match"
    assert message =~ "--nth 1..2"

    out = Stmt.replace(src, "go/1", "x", "tick()", "tock()", nth: 2)
    assert out =~ "other(x)\n    tock()"
  end

  test "reaches inside an anonymous fn — a call in Enum.each(fn -> end) had no verb" do
    src = """
    defmodule Fnx do
      def go(entries, id) do
        Enum.each(entries, fn %{name: name} ->
          spawn_window(id, instantiate(name))
        end)
      end
    end
    """

    assert "spawn_window(id, instantiate(name))" in Stmt.list(src, "go/2", "entries, id")

    out =
      Stmt.replace(
        src,
        "go/2",
        "entries, id",
        "spawn_window(id, instantiate(name))",
        "spawn_window(id, instantiate(name, id))"
      )

    assert out =~ "spawn_window(id, instantiate(name, id))"
    assert out =~ "Enum.each(entries, fn %{name: name} ->"
  end

  test "a multi-statement fn body lists each of its statements" do
    src = """
    defmodule Fnx do
      def go(list) do
        Enum.map(list, fn x ->
          first(x)
          second(x)
        end)
      end
    end
    """

    statements = Stmt.list(src, "go/1", "list")

    assert "first(x)" in statements
    assert "second(x)" in statements
  end

  test "an unknown clause is refused before any statement is looked for" do
    assert {:error, message} = Stmt.list(@src, "nope/9", "x")
    assert message =~ "no clause nope/9"
  end
end
