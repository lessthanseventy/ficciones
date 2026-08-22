defmodule Aleph.WorldTemplatesTest do
  # The nix-owned world-archetype registry (capabilities): starter type/paths/roster the author
  # face's "new world" composes a funes row from. Distinct from Aleph.Profiles' coworker archetypes.
  use ExUnit.Case, async: true

  alias Aleph.WorldTemplates

  test "the three world archetypes exist" do
    assert MapSet.new(WorldTemplates.names()) == MapSet.new([:code, :life, :blank])
  end

  test "the code template carries a surveyor+builder starter roster over modules/*" do
    t = WorldTemplates.template(:code)
    assert t.type == "code"
    assert t.paths == ["modules/*"]
    assert Enum.map(t.roster, & &1.archetype) == [:surveyor, :builder]
  end

  test "the blank template is empty (no roster, no paths)" do
    t = WorldTemplates.template(:blank)
    assert t.type == "blank"
    assert t.roster == []
    assert t.paths == []
  end

  test "template/1 raises on an unknown key" do
    assert_raise KeyError, fn -> WorldTemplates.template(:nope) end
  end

  test "new_world_attrs builds register_world attrs from a template + name (string-keyed roster)" do
    attrs = WorldTemplates.new_world_attrs(:code, "Ficciones2")

    assert attrs.name == "Ficciones2"
    assert attrs.type == "code"
    assert attrs.scope == "machine"
    assert attrs.paths == ["modules/*"]
    # roster is the funes wire shape: string-keyed maps, matching the seed roster
    assert attrs.roster == [
             %{"archetype" => "surveyor", "name" => "surveyor"},
             %{"archetype" => "builder", "name" => "builder"}
           ]
  end

  test "new_world_attrs from :blank yields an empty roster" do
    assert WorldTemplates.new_world_attrs(:blank, "Scratch").roster == []
  end
end
