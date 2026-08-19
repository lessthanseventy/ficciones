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

    test "permissions pass through untouched" do
      assert Profiles.render(
               %Profile{name: "t", permissions: %{"yoloMode" => true}},
               @base_settings,
               @base_mcp
             ).permissions ==
               %{"yoloMode" => true}
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

  describe "the tlon profile — machine-scope funes citizen + sandboxed" do
    test "wires funes on the machine scope, keeps the manos/pi adapter, sockets allowed in the sandbox" do
      p = Profiles.fetch("tlon")
      # Not severed: a funes server whose token binds to the machine thread (via the env
      # funes-cli.sh mints from), so Tlön gets its OWN dossier/logbook without a project bleed.
      assert %{"funes" => funes} = p.mcp
      assert funes["url"] == "${FUNES_MCP_URL}"
      assert funes["headers"]["Authorization"] =~ "funes-cli.sh bearer"
      # The manos/pi funes adapter (brief + auto-capture) is KEPT now that it points at the machine thread.
      assert p.drop_extensions == []
      assert p.sandbox["network"]["allowAllUnixSockets"] == true
    end

    test "cuts the boundary-crossing funes tools (self-containment) but keeps the record/read verbs" do
      funes = Profiles.fetch("tlon").mcp["funes"]
      # consult_peer (ask other local coworkers) + open/close_thread (cross-thread) break isolation.
      for cut <- ["consult_peer", "open_thread", "close_thread"], do: assert(cut in funes["excludeTools"])
      # its own machine-work loop stays: post/bank/record/dossier/habit.
      for kept <- ["post_message", "bank_fact", "record_done", "get_dossier", "propose_habit"],
          do: assert(kept in funes["directTools"])
    end

    test "adds the generic footer back (its own package, not swept up by the manos/pi drop)" do
      p = Profiles.fetch("tlon")
      assert Enum.any?(p.add_extensions, &String.ends_with?(&1, "/modules/manos/footer/src/footer.ts"))
      # and the footer path does NOT match the funes-adapter drop, so it isn't a fight
      refute Enum.any?(p.add_extensions, &String.contains?(&1, "/manos/pi/"))
    end

    test "carries a per-coworker permission policy — yolo (autonomous), but sudo + secrets stay denied" do
      perms = Profiles.fetch("tlon").permissions
      # autonomous coworker: asks auto-approve so an unattended agent never stalls...
      assert perms["yoloMode"] == true
      # ...but yolo is deny-preserving, so the fence holds: no unattended sudo, no credential reads,
      # and the catastrophic-command floor (deny is the one verdict yolo cannot re-permit)
      assert perms["permission"]["bash"]["sudo *"] == "deny"
      assert perms["permission"]["bash"]["rm -rf /*"] == "deny"
      assert perms["permission"]["bash"]["mkfs*"] == "deny"
      assert perms["permission"]["path"]["*.env"] == "deny"
      assert perms["permission"]["path"]["~/.ssh/*"] == "deny"
      assert perms["permission"]["path"]["~/.pi/agent/auth.json"] == "deny"
      # the point of all this: normal work just runs
      assert perms["permission"]["*"] == "allow"
    end

    test "drives ollama-first (glm-5.2) — no pi-multi-account Claude impersonation by default" do
      assert Profiles.fetch("tlon").model == %{
               provider: "ollama-cloud",
               model: "glm-5.2",
               thinking: "medium"
             }
    end

    test "unknown profile → nil" do
      assert Profiles.fetch("nope") == nil
    end

    test "repo/0 is the ficciones root — the single path the Tlön claude-code window shares, not a second copy" do
      assert Profiles.repo() =~ ~r{ficciones$}
    end

    test "an operator override (Aleph.Config) is merged over the compiled model" do
      dir = Path.join(System.tmp_dir!(), "aleph-prof-cfg-#{System.unique_integer([:positive])}")
      path = Path.join(dir, "config.json")
      Aleph.Config.put_coworker_model("tlon", %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}, path)

      previous = Application.get_env(:aleph, :config_path)
      Application.put_env(:aleph, :config_path, path)

      on_exit(fn ->
        Application.put_env(:aleph, :config_path, previous)
        File.rm_rf!(dir)
      end)

      assert Profiles.fetch("tlon").model == %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}
    end
  end

  describe "the tertius profile — the Orbis Tertius meta agent (slice 3)" do
    test "carries the meta-agent persona as its system_prompt, on a cheap glm driver" do
      p = Profiles.fetch("tertius")
      assert p.model == %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}
      # The persona is what distinguishes tertius from the tlon coworker — it must be present and
      # spell out the vantage-not-worker role, or it's just a second glm coworker.
      assert p.system_prompt =~ "tertius-machine"
      assert p.system_prompt =~ "synthesis"
      assert p.system_prompt =~ "root"
    end

    test "render carries the persona through to the materialised files" do
      assert Profiles.render(Profiles.fetch("tertius"), @base_settings, @base_mcp).system_prompt =~ "tertius-machine"
    end

    test "gets the cross-leaf machine_overview read (slice 4) that the tlon worker does not" do
      tertius = Profiles.fetch("tertius").mcp["funes"]["directTools"]
      assert "machine_overview" in tertius
      # ...and it's the ONE tool that separates the synthesizer from the self-contained worker.
      refute "machine_overview" in Profiles.fetch("tlon").mcp["funes"]["directTools"]
    end
  end

  describe "the model ring — what the settings `m` verb cycles" do
    test "ollama-only — the anthropic-via-pi impersonation path isn't a ring entry" do
      assert [%{provider: "ollama-cloud", model: "glm-5.2"} | _] = Profiles.model_ring()
      assert Enum.all?(Profiles.model_ring(), &(&1.provider == "ollama-cloud"))
    end

    test "next_model advances and wraps; unknown or nil restarts at the head" do
      [first, second | _] = Profiles.model_ring()
      assert Profiles.next_model(first) == second
      assert Profiles.next_model(List.last(Profiles.model_ring())) == first
      assert Profiles.next_model(nil) == first
      assert Profiles.next_model(%{provider: "x", model: "y"}) == first
    end
  end

  describe "materialise!/2 — writes the config dir from a base" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "aleph-prof-#{System.unique_integer([:positive])}")
      base = Path.join(tmp, "agent")
      File.mkdir_p!(base)
      File.write!(Path.join(base, "settings.json"), Jason.encode!(@base_settings))
      File.write!(Path.join(base, "mcp.json"), Jason.encode!(@base_mcp))

      for f <- ~w(auth.json models.json models-store.json provider-failover.json),
          do: File.write!(Path.join(base, f), "{}")

      on_exit(fn -> File.rm_rf!(tmp) end)
      %{base: base, root: Path.join(tmp, "profiles")}
    end

    test "writes settings/mcp/sandbox and symlinks the shared files", %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root)
      assert dir == Path.join(root, "tlon")

      settings = Jason.decode!(File.read!(Path.join(dir, "settings.json")))
      # the manos/pi funes adapter is KEPT now (brief + auto-capture pointed at the machine thread)
      assert Enum.any?(settings["extensions"], &String.contains?(&1, "/manos/pi/"))
      mcp = Jason.decode!(File.read!(Path.join(dir, "mcp.json")))
      assert mcp["mcpServers"]["funes"]["url"] == "${FUNES_MCP_URL}"
      assert "consult_peer" in mcp["mcpServers"]["funes"]["excludeTools"]
      assert Jason.decode!(File.read!(Path.join(dir, "sandbox.json")))["enabled"] == true
      # permission-system fail-closes to "ask" without a config in PI_CODING_AGENT_DIR, so the
      # coworker gets its own config in the nested extension dir
      perms = Jason.decode!(File.read!(Path.join(dir, "extensions/pi-permission-system/config.json")))
      assert perms["yoloMode"] == true
      assert perms["permission"]["bash"]["sudo *"] == "deny"
      # the shared files are symlinks back to the base — one credential store, one model catalog,
      # one failover policy (so pi-multi-account fails this coworker's Claude over to ollama.com glm)
      assert File.read_link!(Path.join(dir, "auth.json")) == Path.join(base, "auth.json")

      assert File.read_link!(Path.join(dir, "provider-failover.json")) ==
               Path.join(base, "provider-failover.json")
    end

    test "a profile with a persona writes system_prompt.md (the tertius meta agent)", %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root)
      assert File.read!(Path.join(dir, "system_prompt.md")) =~ "tertius-machine"
    end

    test "writes the coworker's persistence-free tmux.conf — fresh on rebuild, never resurrected",
         %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root)
      conf = File.read!(Path.join(dir, "tmux.conf"))
      # the interactive bits travel with the coworker...
      assert conf =~ "set -g mouse on"
      assert conf =~ "set -s extended-keys on"
      assert conf =~ "set -g mode-style"
      # ...the persistence plugins deliberately do NOT
      refute conf =~ "resurrect"
      refute conf =~ "continuum"
    end

    test "the socket name is per-profile, so no coworker shares the user's default server" do
      assert Profiles.socket("tlon") == "aleph-tlon"
      assert Profiles.socket("desk") == "aleph-desk"
    end

    test "idempotent — a second materialise re-links without error", %{base: base, root: root} do
      Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root)
      assert Profiles.materialise!(Profiles.fetch("tlon"), base: base, root: root) == Path.join(root, "tlon")
    end
  end
end
