defmodule Aleph.Panel.SpacesTest do
  # SPACES picker footer verbs (render/pick are pinned by view_test.exs and board_test.exs already).
  use ExUnit.Case, async: true

  alias Aleph.Panel.Spaces

  test "hints/1 declares the pane's footer verbs" do
    assert Aleph.Panel.hints(Spaces, %{}) == [{"j/k", "spaces"}, {"⏎", "switch"}]
  end
end
