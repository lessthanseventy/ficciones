defmodule Aleph.TextTest do
  # wrap_paragraphs: hard newlines keep their breaks, blank-line runs collapse to ONE empty
  # line between paragraphs — the message-readability seam both chat renderers share.
  use ExUnit.Case, async: true

  alias Aleph.Text

  describe "wrap_paragraphs/2" do
    test "a blank line separates paragraphs with exactly one empty line" do
      assert Text.wrap_paragraphs("first para\n\nsecond para", 40) ==
               ["first para", "", "second para"]
    end

    test "a run of blank lines still yields one separator" do
      assert Text.wrap_paragraphs("a\n\n\n\nb", 40) == ["a", "", "b"]
    end

    test "single newlines keep their breaks — a list survives" do
      assert Text.wrap_paragraphs("- one\n- two", 40) == ["- one", "- two"]
    end

    test "each paragraph wraps to the width" do
      assert Text.wrap_paragraphs("alpha beta gamma\n\ndelta", 10) ==
               ["alpha beta", "gamma", "", "delta"]
    end

    test "an empty string yields no rows" do
      assert Text.wrap_paragraphs("", 40) == []
    end
  end
end
