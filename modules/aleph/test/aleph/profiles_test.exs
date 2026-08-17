defmodule Aleph.ProfilesTest do
  @moduledoc "The coworker-profile registry, the pure render seam, and the materialiser (into a tmp dir)."
  use ExUnit.Case, async: true

  alias Aleph.Profile
  alias Aleph.Profiles

  @base_settings %{
    "extensions" => [
      "/repo/modules/manos/pi/src/extension.ts",
      "/repo/modules/manos/consult/src/extension.ts",
      "/repo/modules/manos/lsp/src/extension.ts",
      "/repo/modules/manos/reload/src/extension.ts"
    ],
    "defaultProvider" => "ollama-cloud",
    "defaultModel" => "deepseek-v4-flash",
    "skills" => ["/repo/modules/manos/skills/*"]
  }
  @base_mcp %{"mcpServers" => %{"funes" => %{"url" => "http://x/mcp"}}}

  describe "render/3 — a profile is a diff over the base config" do
    test "drops the named extensions, keeps the rest" do
      r = Profiles.render(%Profile{name: "t", drop_extensions: ["/manos/pi/"]}, @base_settings, @base_mcp)
      refute Enum.any?(r.settings["extensions"], &String.contains?(&1, "/manos/pi/"))
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/manos/lsp/"))
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/manos/consult/"))
    end

    test "mcp :none → empty mcpServers (self-contained); :base → inherits the base" do
      assert Profiles.render(%Profile{name: "t", mcp: :none}, @base_settings, @base_mcp).mcp ==
               %{"mcpServers" => %{}}

      assert Profiles.render(%Profile{name: "t", mcp: :base}, @base_settings, @base_mcp).mcp == @base_mcp
    end

    test "model override replaces the base defaults; nil inherits them" do
      r =
        Profiles.render(
          %Profile{name: "t", model: %{provider: "ollama-cloud", model: "deepseek-v4-pro", thinking: "high"}},
          @base_settings,
          @base_mcp
        )

      assert r.settings["defaultModel"] == "deepseek-v4-pro"
      assert r.settings["defaultThinkingLevel"] == "high"

      assert Profiles.render(%Profile{name: "t"}, @base_settings, @base_mcp).settings["defaultModel"] ==
               "deepseek-v4-flash"
    end

    test "sandbox passes through untouched" do
      assert Profiles.render(%Profile{name: "t", sandbox: %{"enabled" => true}}, @base_settings, @base_mcp).sandbox ==
               %{"enabled" => true}
    end

    test "add_extensions appends on top of the base (a coworker-specific / not-yet-flake-registered extension)" do
      r =
        Profiles.render(
          %Profile{name: "t", add_extensions: ["/repo/modules/manos/footer/src/footer.ts"]},
          @base_settings,
          @base_mcp
        )

      assert "/repo/modules/manos/footer/src/footer.ts" in r.settings["extensions"]
      # the base ones are still there
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/manos/lsp/"))
    end

    test "add wins over drop, and a doubly-present extension appears once" do
      # add_extensions survives a drop pattern it would otherwise match...
      r =
        Profiles.render(
          %Profile{
            name: "t",
            drop_extensions: ["/manos/pi/"],
            add_extensions: ["/repo/modules/manos/pi/src/extension.ts"]
          },
          @base_settings,
          @base_mcp
        )

      assert "/repo/modules/manos/pi/src/extension.ts" in r.settings["extensions"]

      # ...and once the base already lists an add, it isn't duplicated (idempotent post-home:switch).
      base_with_footer = Map.update!(@base_settings, "extensions", &(&1 ++ ["/repo/modules/manos/footer/src/footer.ts"]))

      r2 =
        Profiles.render(
          %Profile{name: "t", add_extensions: ["/repo/modules/manos/footer/src/footer.ts"]},
          base_with_footer,
          @base_mcp
        )

      assert Enum.count(r2.settings["extensions"], &(&1 == "/repo/modules/manos/footer/src/footer.ts")) == 1
    end
  end

  describe "the tlon profile — self-contained + sandboxed" do
    test "no funes MCP, drops the funes-brief extension, sockets allowed in the sandbox" do
      p = Profiles.fetch("tlon")
      assert p.mcp == :none
      assert p.drop_extensions == ["/manos/pi/"]
      assert p.sandbox["network"]["allowAllUnixSockets"] == true
    end

    test "adds the generic footer back (its own package, not swept up by the manos/pi drop)" do
      p = Profiles.fetch("tlon")
      assert Enum.any?(p.add_extensions, &String.ends_with?(&1, "/modules/manos/footer/src/footer.ts"))
      # and the footer path does NOT match the funes-adapter drop, so it isn't a fight
      refute Enum.any?(p.add_extensions, &String.contains?(&1, "/manos/pi/"))
    end

    test "drives on a capable glm — an orchestrator, not flash" do
      assert Profiles.fetch("tlon").model == %{provider: "ollama-cloud", model: "glm-5.1", thinking: "medium"}
    end

    test "unknown profile → nil" do
      assert Profiles.fetch("nope") == nil
    end
  end

  describe "materialise!/2 — writes the config dir from a base" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "aleph-prof-#{System.unique_integer([:positive])}")
      base = Path.join(tmp, "agent")
      File.mkdir_p!(base)
      File.write!(Path.join(base, "settings.json"), Jason.encode!(@base_settings))
      File.write!(Path.join(base, "mcp.json"), Jason.encode!(@base_mcp))
      for f <- ~w(auth.json models.json models-store.json), do: File.write!(Path.join(base, f), "{}")
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{base: base, root: Path.join(tmp, "profiles")}
    end

    test "writes settings/mcp/sandbox and symlinks the shared files", %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root)
      assert dir == Path.join(root, "tlon")

      settings = Jason.decode!(File.read!(Path.join(dir, "settings.json")))
      refute Enum.any?(settings["extensions"], &String.contains?(&1, "/manos/pi/"))
      assert Jason.decode!(File.read!(Path.join(dir, "mcp.json"))) == %{"mcpServers" => %{}}
      assert Jason.decode!(File.read!(Path.join(dir, "sandbox.json")))["enabled"] == true
      # the shared files are symlinks back to the base — one credential store, one model catalog
      assert File.read_link!(Path.join(dir, "auth.json")) == Path.join(base, "auth.json")
    end

    test "idempotent — a second materialise re-links without error", %{base: base, root: root} do
      Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root)
      assert Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root) == Path.join(root, "tlon")
    end
  end
end
