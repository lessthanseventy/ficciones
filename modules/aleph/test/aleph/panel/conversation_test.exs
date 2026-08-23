defmodule Aleph.Panel.ConversationTest do
  # The cockpit chat box: messages plus the trailing presence indicator — explicit thinking
  # (accent) outranks tmux-inferred working (dim). Headless, pure render.
  use ExUnit.Case, async: true

  alias Aleph.Panel.Conversation

  @rect %{x: 0, y: 0, w: 60, h: 40}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  defp style_of(rows, needle) do
    Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t =~ needle, do: s end) end)
  end

  test "a blank row separates messages; body paragraphs render with a blank line" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "a", body: "one\n\ntwo"}, %{author: "b", body: "three"}]},
        @rect
      )

    texts = lines(rows)
    # message one: first line, paragraph gap, second paragraph (hanging indent)
    assert texts |> Enum.drop_while(&(&1 != "a: one")) |> Enum.take(5) == ["a: one", "", "  two", "", "b: three"]
  end

  test "no presence data renders just the messages — no indicator row" do
    text =
      %{title: "t", messages: [%{author: "hronir", body: "hi"}]}
      |> Conversation.render(@rect)
      |> lines()
      |> Enum.join("\n")

    refute text =~ "thinking"
    refute text =~ "working"
  end

  test "a thinking agent renders an accent indicator after the messages" do
    rows =
      Conversation.render(
        %{title: "t", messages: [%{author: "hronir", body: "hi"}], thinking: ["tertius"], working: []},
        @rect
      )

    assert rows |> lines() |> Enum.join("\n") =~ "⋯ tertius is thinking…"
    assert style_of(rows, "is thinking") == :accent
  end

  test "a working (tmux-inferred) agent renders dim; both can show at once" do
    rows =
      Conversation.render(
        %{title: "t", messages: [], thinking: ["tertius"], working: ["hronir"]},
        @rect
      )

    text = rows |> lines() |> Enum.join("\n")
    assert text =~ "⋯ tertius is thinking…"
    assert text =~ "⋯ hronir is working…"
    assert style_of(rows, "is working") == :dim
  end
end
