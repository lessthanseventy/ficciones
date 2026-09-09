defmodule Menard.ClauseTest do
  # The clause verbs — what replaces the grep/sed dance: address a clause by `name/arity` and a
  # head pattern (its args, as written), then replace its body, delete it, or insert a new clause
  # after it. Patches, not reprints: everything else in the file is byte-identical.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule Demo do
    # first
    def go(:a), do: 1

    # second
    def go(:b) do
      2
    end

    def go(other), do: other
  end
  """

  test "replace_body swaps one clause's body, one-liner or block, leaving the rest" do
    out = Clause.replace_body(@src, "go/1", ":b", "20")
    assert out =~ "def go(:b), do: 20"
    refute out =~ "\n    2\n"
    assert out =~ "# first\n  def go(:a), do: 1"
    assert out =~ "def go(other), do: other"
  end

  test "delete removes the clause (and the comment glued above it), nothing else" do
    out = Clause.delete(@src, "go/1", ":a")
    refute out =~ "go(:a)"
    refute out =~ "# first"
    assert out =~ "# second\n  def go(:b) do"
    assert out =~ "def go(other), do: other"
  end

  test "insert_after adds a clause right after the addressed one" do
    out = Clause.insert_after(@src, "go/1", ":a", "def go(:c), do: 3")
    assert out =~ "def go(:a), do: 1\n  def go(:c), do: 3\n"
  end

  test "insert_before adds a clause right before the addressed one, at its indent" do
    out = Clause.insert_before(@src, "go/1", ":a", "def go(nil), do: 0")
    assert out =~ "# first\n  def go(nil), do: 0\n  def go(:a), do: 1"
  end

  test "an unknown clause is an error naming the candidates" do
    assert {:error, msg} = Clause.replace_body(@src, "go/1", ":zzz", "1")
    assert msg =~ "go/1" and msg =~ ":a"
    assert {:error, _} = Clause.delete(@src, "nope/0", "", [])
  end

  test "a file with several modules: Mod.name/arity scopes the edit; a bare name they share is refused" do
    src = "defmodule A do\n  def run(x), do: x\nend\n\ndefmodule B do\n  def run(x), do: x\nend\n"

    assert Clause.replace_body(src, "B.run/1", "x", "x + 1") ==
             "defmodule A do\n  def run(x), do: x\nend\n\ndefmodule B do\n  def run(x), do: x + 1\nend\n"

    assert {:error, msg} = Clause.replace_body(src, "run/1", "x", "x + 1")
    assert msg =~ "A, B" and msg =~ "Mod.run/1"
    assert {:error, msg} = Clause.replace_body(src, "C.run/1", "x", "x + 1")
    assert msg =~ "no module C"
  end

  test "a guard is part of the head" do
    src = "defmodule G do\n  def f(x) when is_integer(x), do: x\n  def f(x), do: 0\nend\n"

    assert Clause.replace_body(src, "f/1", "x when is_integer(x)", "x * 2") =~
             "def f(x) when is_integer(x), do: x * 2"

    assert Clause.delete(src, "f/1", "x") == "defmodule G do\n  def f(x) when is_integer(x), do: x\nend\n"
  end

  describe "rewrite — the whole clause, head included" do
    test "changes the head, which replace_body structurally cannot" do
      out = Clause.rewrite(@src, "go/1", ":a", "def go(:a, extra), do: extra")
      assert out =~ "def go(:a, extra), do: extra"
      assert out =~ "# first"
      assert out =~ "def go(other), do: other"
    end

    test "adds a guard, keeping the rest of the file" do
      out = Clause.rewrite(@src, "go/1", "other", "def go(other) when is_integer(other), do: other")
      assert out =~ "def go(other) when is_integer(other), do: other"
      assert out =~ "def go(:a), do: 1"
    end

    test "a multi-line clause is shifted out to the clause's own column" do
      out = Clause.rewrite(@src, "go/1", ":a", "def go(:a) do\n  1 + 1\nend")
      assert out =~ "  def go(:a) do\n    1 + 1\n  end"
    end

    test "refuses a bare expression — that would leave a def replaced by an expression" do
      assert {:error, message} = Clause.rewrite(@src, "go/1", ":a", "1 + 1")
      assert message =~ "needs a whole clause"
    end

    test "refuses code that does not parse" do
      assert {:error, message} = Clause.rewrite(@src, "go/1", ":a", "def go(:a) do")
      assert message =~ "not parseable"
    end
  end

  describe "head matching tolerates the parens people copy off the def line" do
    test "`(:b)` finds the clause whose head is `:b`" do
      assert Clause.replace_body(@src, "go/1", "(:b)", "20") =~ "def go(:b), do: 20"
    end

    test "the parens may wrap the args of a GUARDED head, with the guard left outside" do
      src = "defmodule D do\n  def only(x) when is_integer(x), do: x\nend\n"
      out = Clause.replace_body(src, "only/1", "(x) when is_integer(x)", ":int")
      assert out =~ "def only(x) when is_integer(x), do: :int"
    end

    test "parens that are not a wrapper stay put — and the miss names the real head" do
      src = "defmodule D do\n  def pair(a, b), do: {a, b}\nend\n"
      assert {:error, message} = Clause.replace_body(src, "pair/2", "(a), (b)", ":ok")
      assert message =~ "have: `a, b`"
    end
  end

  describe "insert_at — a new function, with no sibling clause to anchor to" do
    @mixed """
    defmodule M do
      def one, do: 1

      def two, do: 2

      defp helper, do: :h
    end
    """

    test "a defp lands after the last private function" do
      out = Clause.insert_at(@mixed, nil, nil, "defp fresh, do: :f")
      assert out =~ "defp helper, do: :h\n\n  defp fresh, do: :f"
    end

    test "a def lands after the last PUBLIC function, above the privates" do
      out = Clause.insert_at(@mixed, nil, nil, "def three, do: 3")
      assert out =~ "def two, do: 2\n\n  def three, do: 3"
      assert out =~ "def three, do: 3\n\n  defp helper"
    end

    test ":top puts it before the module's first definition" do
      out = Clause.insert_at(@mixed, nil, :top, "def zero, do: 0")
      assert out =~ "def zero, do: 0\n\n  def one, do: 1"
    end

    test ":bottom puts it after the module's last definition" do
      out = Clause.insert_at(@mixed, nil, :bottom, "def last, do: :l")
      assert out =~ "defp helper, do: :h\n\n  def last, do: :l"
    end

    test "an empty module takes the code just inside it" do
      out = Clause.insert_at("defmodule E do\nend\n", nil, nil, "def only, do: 1")
      assert out =~ "defmodule E do\n  def only, do: 1\nend"
    end

    test "a @doc above the code doesn't get mistaken for the thing being inserted" do
      out = Clause.insert_at(@mixed, nil, nil, "@doc \"h\"\ndefp documented, do: :d")
      assert out =~ "defp helper, do: :h\n\n  @doc \"h\"\n  defp documented, do: :d"
    end

    test "names the module in a file that has several" do
      src = "defmodule A do\n  def a, do: 1\nend\n\ndefmodule B do\n  def b, do: 2\nend\n"
      out = Clause.insert_at(src, "B", nil, "def added, do: 3")
      assert out =~ "def b, do: 2\n\n  def added, do: 3"
      refute out =~ "def a, do: 1\n\n  def added"
    end

    test "refuses an unnamed module when the file has several" do
      src = "defmodule A do\n  def a, do: 1\nend\n\ndefmodule B do\n  def b, do: 2\nend\n"
      assert {:error, message} = Clause.insert_at(src, nil, nil, "def added, do: 3")
      assert message =~ "several modules"
    end

    test "names the modules that exist when the one asked for does not" do
      assert {:error, message} = Clause.insert_at(@mixed, "Nope", nil, "def x, do: 1")
      assert message =~ "no module Nope"
      assert message =~ "M"
    end
  end

  describe "delete takes the attributes attached to the clause" do
    @attrs """
    defmodule A do
      @impl Panel
      def go(:a), do: 1

      @impl Panel
      def go(:b), do: 2

      @impl Panel
      def go(:c), do: 3
    end
    """

    test "an @impl above a MIDDLE clause goes with it, or it re-attaches to the next one" do
      out = Clause.delete(@attrs, "go/1", ":b")

      refute out =~ "go(:b)"
      # exactly two @impl left, one per surviving clause — three would be the redefining warning
      assert length(String.split(out, "@impl")) - 1 == 2
    end

    test "a @doc and @spec above the clause go with it" do
      src = """
      defmodule A do
        @doc "the one"
        @spec go(atom()) :: integer()
        def go(:a), do: 1

        def other, do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      refute out =~ "@doc"
      refute out =~ "@spec"
      assert out =~ "def other, do: 2"
    end

    test "a comment written ABOVE the attribute goes too — the whole block is the clause" do
      src = """
      defmodule A do
        # why this exists
        @impl true
        def go(:a), do: 1

        def other, do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      refute out =~ "why this exists"
      refute out =~ "@impl"
    end

    test "only CONTIGUOUS attributes count — a @doc on the FIRST clause survives deleting a later one" do
      src = """
      defmodule A do
        @doc "documents go/1"
        def go(:a), do: 1
        def go(:b), do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":b")

      assert out =~ ~s(@doc "documents go/1")
      assert out =~ "def go(:a), do: 1"
      refute out =~ "go(:b)"
    end

    test "an attribute that is NOT clause-attached is left where it is" do
      src = """
      defmodule A do
        @timeout 5_000
        def go(:a), do: 1

        def other, do: @timeout
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      assert out =~ "@timeout 5_000"
      refute out =~ "go(:a)"
    end
  end

  describe "visibility — every clause at once" do
    @multi """
    defmodule A do
      @doc "what it does"
      @spec go(atom()) :: integer()
      def go(:a), do: 1
      def go(:b), do: 2
      def go(_other), do: 0

      def other, do: :ok
    end
    """

    test "privatize flips EVERY clause — a half-flipped function does not compile" do
      out = Clause.visibility(@multi, "go/1", :private)

      assert length(String.split(out, "defp go(")) - 1 == 3
      refute out =~ "\n  def go("
      # the untouched neighbour keeps its visibility
      assert out =~ "def other, do: :ok"
    end

    test "privatize drops the @doc, which Elixir would discard with a warning" do
      out = Clause.visibility(@multi, "go/1", :private)

      refute out =~ "@doc"
      # @spec is legal on a defp and stays
      assert out =~ "@spec go(atom()) :: integer()"
    end

    test "publicize flips them back" do
      private = Clause.visibility(@multi, "go/1", :private)
      out = Clause.visibility(private, "go/1", :public)

      assert length(String.split(out, "\n  def go(")) - 1 == 3
      refute out =~ "defp go("
    end

    test "keeps the family — a defmacrop becomes a defmacro, not a def" do
      src = "defmodule A do\n  defmacrop m(x), do: x\nend\n"
      assert Clause.visibility(src, "m/1", :public) =~ "defmacro m(x), do: x"
    end

    test "already at the wanted visibility is a no-op, byte for byte" do
      assert Clause.visibility(@multi, "go/1", :public) == @multi
    end

    test "a function that isn't there is an error, not a silent no-op" do
      assert {:error, message} = Clause.visibility(@multi, "nope/9", :private)
      assert message =~ "nope/9"
    end

    test "only the named function moves" do
      out = Clause.visibility(@multi, "other/0", :private)

      assert out =~ "defp other, do: :ok"
      assert out =~ "def go(:a), do: 1"
    end
  end
end
