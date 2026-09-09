defmodule Menard.AmbiguityTest do
  # Two clauses can share a head — an insert beside a twin is the usual way — and acting on "the
  # first" silently is how a delete eats the clause a verb has just written.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule Dup do
    def pick(x), do: {:first, x}

    def other(y), do: y

    def pick(x), do: {:second, x}
  end
  """

  test "a head two clauses share is refused, and the message says where they are" do
    assert {:error, message} = Clause.delete(@src, "pick/1", "x")
    assert message =~ "2 clauses of pick/1 share the head"
    assert message =~ "line 2"
    assert message =~ "line 6"
    assert message =~ "--nth 1..2"
  end

  test "--nth picks the one meant, counting in source order" do
    out = Clause.rewrite(@src, "pick/1", "x", "def pick(x), do: {:SECOND, x}", nth: 2)

    assert out =~ "{:first, x}"
    assert out =~ "{:SECOND, x}"
    refute out =~ "{:second, x}"
  end

  test "--nth past the end says so rather than picking the last" do
    assert {:error, message} = Clause.delete(@src, "pick/1", "x", nth: 3)
    assert message =~ "past the 2 clauses"
  end

  test "an unambiguous head still needs no --nth" do
    assert Clause.delete(@src, "other/1", "y") =~ "def pick"
  end
end

defmodule Menard.ClauseCommentTest do
  # A clause and the comment glued above it are one unit to a reader, so `rewrite` takes both.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule C do
    # the old why
    def go(x), do: x
  end
  """

  test "rewrite accepts a leading comment and carries it in" do
    out = Clause.rewrite(@src, "go/1", "x", "# the new why\ndef go(x), do: x * 2")

    assert out =~ "# the new why"
    assert out =~ "def go(x), do: x * 2"
    refute out =~ "the old why"
  end

  test "a bare expression is still refused — the check reads past the comment" do
    assert {:error, message} = Clause.rewrite(@src, "go/1", "x", "# just a comment\n:not_a_clause")
    assert message =~ "needs a whole clause"
  end
end

defmodule Menard.ClauseDocTest do
  # A docstring is a string on an attribute: no other verb reaches it.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule D do
    @doc "the old doc"
    def kept(x), do: x

    def bare(y), do: y
  end
  """

  test "set replaces an existing @doc, heredoc-wrapped at the clause's indent" do
    out = Clause.doc(@src, "kept/1", "x", "A new doc.\n\nWith a second paragraph.")

    assert out =~ ~s(  @doc """\n  A new doc.\n\n  With a second paragraph.\n  """\n  def kept)
    refute out =~ "the old doc"
  end

  test "set adds a @doc to a clause that had none, leaving the other alone" do
    out = Clause.doc(@src, "bare/1", "y", "Doc for bare.")

    assert out =~ ~s(  @doc """\n  Doc for bare.\n  """\n  def bare)
    assert out =~ ~s(@doc "the old doc")
  end

  test "nil deletes the @doc and nothing else" do
    out = Clause.doc(@src, "kept/1", "x", nil)

    refute out =~ "the old doc"
    assert out =~ "def kept(x), do: x"
    assert out =~ "def bare(y), do: y"
  end

  test "deleting a @doc that isn't there is a no-op, not an error" do
    assert Clause.doc(@src, "bare/1", "y", nil) == @src
  end
end

defmodule Menard.BlockRelabelTest do
  # Renaming a test used to mean editing the file as text.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule TTest do
    describe "the old describe" do
      test "the old name" do
        assert 1 == 1
      end
    end
  end
  """

  test "a test's label is renamed, body untouched" do
    out = Block.relabel(@src, "test", "the old name", "the new name")

    assert out =~ ~s(test "the new name" do)
    assert out =~ "assert 1 == 1"
    assert out =~ ~s(describe "the old describe")
  end

  test "a describe's label too" do
    out = Block.relabel(@src, "describe", "the old describe", "the new describe")

    assert out =~ ~s(describe "the new describe" do)
    assert out =~ ~s(test "the old name")
  end

  test "a label that isn't there is refused" do
    assert {:error, message} = Block.relabel(@src, "test", "nope", "x")
    assert message =~ "nope"
  end
end

defmodule Menard.BlockModuleParentTest do
  # `--in` names a parent to append inside; a module is as obvious a parent as a labelled block.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule InMod do
    test "existing" do
      assert true
    end
  end
  """

  test "--in accepts a MODULE, not only a labelled block" do
    out = Block.add(@src, "describe", "a new describe", "assert true", in: "InMod")

    assert out =~ ~s(describe "a new describe" do)
    assert out =~ ~s(test "existing")
  end

  test "adding a defmodule is refused — a --label would become a string module name" do
    assert {:error, message} = Block.add(@src, "defmodule", "InMod", "assert true", [])
    assert message =~ "menard.module add"
  end
end
