defmodule Aleph.Profile do
  @moduledoc """
  A **coworker profile** — the full pi configuration for one space's machine coworker. A space
  (`Aleph.Space`) names a profile; the cockpit materialises it into a `PI_CODING_AGENT_DIR` and
  launches the coworker with it. Profiles differ on the four dimensions a coworker actually varies
  on (design: `docs/plans/2026-08-17-pi-coworker-profiles-design.md`):

    * **tool / MCP surface** — `mcp` (`:base` inherit, `:none` self-contained, or an explicit
      `%{server => config}`), `drop_extensions` (which base pi extensions to omit), and
      `add_extensions` (extensions to add ON TOP, by absolute path — a coworker-specific extension,
      or one the flake hasn't registered into the base yet, so it loads at the next cockpit restart
      without a `home:switch`).
    * **model + thinking** — `model` (`%{provider, model, thinking}`, or `nil` to inherit the base
      defaults).
    * **system prompt / persona** — `system_prompt` (materialised to a file, passed as
      `--append-system-prompt`).
    * **sandbox** — `sandbox` (a pi-sandbox `sandbox.json` map, or `nil` for unconfined). Scoped to
      the profile because pi-sandbox reads `sandbox.json` from `PI_CODING_AGENT_DIR`.

  A profile is a small DIFF from the base `~/.pi/agent` config, not a full re-declaration — the base
  (extensions, skills, model catalog, auth) stays the single source of truth; the profile drops,
  replaces, and overlays.
  """
  @enforce_keys [:name]
  defstruct name: nil,
            drop_extensions: [],
            add_extensions: [],
            mcp: :base,
            model: nil,
            system_prompt: nil,
            sandbox: nil,
            permissions: nil

  @type t :: %__MODULE__{
          name: String.t(),
          drop_extensions: [String.t()],
          add_extensions: [String.t()],
          mcp: :base | :none | map(),
          model: %{provider: String.t(), model: String.t(), thinking: String.t()} | nil,
          system_prompt: String.t() | nil,
          sandbox: map() | nil,
          permissions: map() | nil
        }
end

defmodule Aleph.Profiles do
  @moduledoc """
  The coworker-profile registry + materialiser. `fetch/1` looks a profile up by name; `render/3`
  is the pure seam (profile + base config → the files a config dir needs); `materialise!/1` is the
  IO wrapper that writes `~/.pi/profiles/<name>/` at cockpit start.

  Materialised layout (`PI_CODING_AGENT_DIR`):

      ~/.pi/profiles/<name>/
        settings.json     profile-specific — base settings with extensions dropped + model overridden
        mcp.json          profile-specific — the profile's MCP servers (`{}` = self-contained)
        sandbox.json      profile-specific — pi-sandbox allowlist (only if profile.sandbox)
        extensions/pi-permission-system/config.json
                          profile-specific — permission policy + yoloMode (only if profile.permissions)
        system_prompt.md  profile-specific — the persona (only if profile.system_prompt)
        tmux.conf         profile-specific — the persistence-free config its private tmux
                          server (`tmux -L aleph-<name>`) boots from (see `socket/1`)
        auth.json      ↳ symlink to ~/.pi/agent/auth.json       (shared credentials)
        models.json    ↳ symlink to ~/.pi/agent/models.json     (shared model catalog)
        models-store.json ↳ symlink                             (shared)
        provider-failover.json ↳ symlink                        (shared failover policy — Claude→glm)
        keybindings.json ↳ symlink                              (shared keymap — Ctrl+P/N nav)
        sessions/         its own — each coworker resumes its own thread (reload --continue)

  Idempotent + self-healing: re-materialised every cockpit start, so editing a profile + restarting
  the cockpit is the whole loop — no `home:switch`.

  ## The `tertius` coworker

  One coworker profile: `tertius`, the Tlön center — the Orbis Tertius meta agent
  (`tertius-machine`), glm-5.2, on the root machine thread. Design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`.

  - **Machine-scope funes citizen.** Its MCP (`@tertius_funes_mcp`) binds every token to scope
    `machine` (via `funes-cli.sh bearer`), so its posts/facts/dones stay on machine threads, off
    project threads (DB scope CHECK). `directTools` are the record/read verbs + `machine_overview`
    (the cross-leaf read); `excludeTools` cuts the cross-thread verbs (`consult_peer`, `open_thread`,
    `close_thread`) for self-containment. Model-to-model consultation is `/consult`+`/fresh`.
  - **Driver.** glm-5.2 (ollama). Real Claude is the `hronir` window, not a driver here.
  - **Sandboxed + yolo permissions.** `@tlon_sandbox` + `@tlon_permissions`: `yoloMode` auto-approves
    asks so an autonomous coworker never stalls, but yolo is deny-PRESERVING, so the
    catastrophic-command + secret-path floor still holds.
  """
  alias Aleph.Profile

  # Single-user machine — the repo the coworker writes in (matches flake.nix's `repo`). Used for the
  # Tlön sandbox's write allowlist.
  @repo "/home/andrew/projects/ficciones"

  # Every coworker runs on its OWN tmux server (socket `aleph-<profile>`), booted from the
  # persistence-free tmux.conf below — never the user's default server, whose resurrect+continuum
  # would resurrect a torn-down coworker with stale identity/env. The interactive bits of the
  # machine tmux config (mouse, extended keys, vi copy-mode) minus every persistence plugin, plus
  # the chrome-off options the launcher used to chain on (aleph draws the Tlön header itself).
  @coworker_tmux_conf """
  # Generated by Aleph.Profiles — the per-coworker tmux server config (persistence-free).
  # A coworker comes up FRESH on every rebuild; the persistence plugins stay on the user's own tmux.
  set -s escape-time 10
  set -s extended-keys on
  set -s extended-keys-format csi-u
  set -as terminal-features 'xterm*:extkeys'
  set -s default-terminal tmux-256color
  set -g history-limit 50000
  set -g mouse on
  set -g base-index 1
  set -g pane-base-index 1
  set -g mode-keys vi
  set -g status off
  set -g 'status-format[0]' ''
  set -g pane-border-status off
  set -g mode-style 'bg=#3b4261,fg=#c0caf5'
  """

  # The Tlön coworker's sandbox (pi-sandbox `sandbox.json`). Permissive enough that the manos tooling
  # keeps working under bubblewrap — the footgun class this session kept hitting:
  #   * allowAllUnixSockets — the lsp shim binds/connects manos-lspd.sock; reload/tmux use sockets too
  #   * allowWrite the repo + /tmp + the socket dir + caches — the daemon writes the socket file, Expert
  #     writes its .expert index, edits land in the repo
  #   * allowedDomains — the hosts this repo's bash tasks reach (mirrors the machine sandbox allowlist)
  # See [[pi-sandbox-manos-allowlist]]. NOT model API calls (pi's own process, not bash).
  #
  # bash runs under `bwrap --unshare-net`, so `127.0.0.1` inside a bash call is the coworker's OWN
  # empty netns, NOT the host's. Tlön's funes is at `FUNES_MCP_URL` = http://127.0.0.1:4041/mcp, so
  # `curl`ing it, `ss -tlnp`, and `mise run funes:doctor|logs` ALWAYS fail here regardless of whether
  # funes is up — `allowLocalBinding` only permits binding within that netns, and the socat proxy that
  # carries external traffic refuses loopback targets with a 403. There is no bash route, by design.
  # The @tlon_funes_mcp tools are unaffected: pi opens that connection from its own process, outside
  # bubblewrap (same reason model API calls work). This matters more for Tlön than for the
  # interactive agent — it runs autonomously, so a bash probe returning 000 with nobody to correct it
  # is how a coworker talks itself into "funes is down" and stops posting. Use the funes tools; a
  # bash probe cannot answer the question.
  @tlon_sandbox %{
    "enabled" => true,
    "network" => %{
      "allowLocalBinding" => true,
      "allowAllUnixSockets" => true,
      # Derived from real Claude + pi session history (not guesswork): the dev-infra hosts this
      # machine's agents actually reach. An allowlist, NOT "*", stays the network fence for the
      # cheap-model coworker; grep the transcripts + extend here when a genuinely new infra host
      # shows up. Keep in sync with the flake's piPermissionSeed twin. See [[pi-sandbox-allowlist]].
      "allowedDomains" => [
        # source control + package registries
        "github.com",
        "*.github.com",
        "*.githubusercontent.com",
        "hex.pm",
        "*.hex.pm",
        "hexdocs.pm",
        "*.hexdocs.pm",
        "registry.npmjs.org",
        "www.npmjs.com",
        "*.npmjs.com",
        "crates.io",
        "static.crates.io",
        "index.crates.io",
        # toolchains + system package infra
        "*.jdx.dev",
        "sh.rustup.rs",
        "static.rust-lang.org",
        "cache.nixos.org",
        "channels.nixos.org",
        "nixos.org",
        # AI / agent infra
        "anthropic.com",
        "*.anthropic.com",
        "claude.com",
        "*.claude.com",
        "claude.ai",
        "ollama.com",
        "*.ollama.com",
        "registry.ollama.ai",
        "pi.dev",
        "modelcontextprotocol.io",
        "*.huggingface.co",
        # language + framework + tool docs
        "elixirforum.com",
        "www.phoenixframework.org",
        "expert-lsp.org",
        "www.typescriptlang.org",
        "react.dev",
        "pnpm.io",
        "playwright.dev",
        "ghostty.org",
        "agent-browser.dev",
        # docs / badges / assets / a11y
        "img.shields.io",
        "deepwiki.com",
        "www.w3.org",
        "dequeuniversity.com",
        "fonts.googleapis.com",
        "fonts.gstatic.com",
        # notifications
        "ntfy.sh",
        "herdr.dev",
        # andrew's own app (Phoenix LiveView)
        "myelin.us",
        "www.myelin.us"
      ]
    },
    "filesystem" => %{
      # Writes: the repo (edits), /tmp + the socket dir (manos-lspd), caches. Never the nix store.
      "allowWrite" => [
        @repo,
        "/tmp",
        "$XDG_RUNTIME_DIR",
        "~/.pi",
        "~/.cache",
        "~/.local"
      ],
      # Reads (prompt-by-default otherwise): the repo, plus /nix/store + ~/.nix-profile so pi reading
      # its OWN install/docs/extensions — and any flake-managed binary's files — never triggers a
      # useless prompt (the store is immutable + world-readable). Config/cache dirs round it out.
      "allowRead" => [
        @repo,
        "/nix/store",
        "~/.nix-profile",
        "~/.config",
        "~/.local",
        "~/.pi",
        "~/.cache"
      ],
      "denyWrite" => [".env", ".env.*", "*.pem", "*.key"]
    }
  }

  # The Tlön coworker's pi-permission-system policy (`extensions/pi-permission-system/config.json`).
  # permission-system reads its "global" config from `PI_CODING_AGENT_DIR` and FAIL-CLOSES to
  # "ask everything" when the file is absent — the same reason sandbox.json is per-profile — so the
  # coworker needs its OWN copy; the flake seeds only `~/.pi/agent`, the interactive agent's dir.
  #
  # This is the per-coworker knob: the interactive agent (flake seed) keeps `ask` for the rare
  # sudo/ambiguous call because a HUMAN is there to answer. Tlön runs AUTONOMOUSLY, so an `ask`
  # would just hang it — `yoloMode: true` auto-approves asks instead (no prompts, no stalls). yolo
  # is deny-PRESERVING, so the fence still holds: `sudo *` and the secret paths are `deny` (not
  # `ask`), so even under yolo the coworker cannot sudo unattended or touch credentials. Everything
  # else inside the sandbox's write allowlist just runs. See [[pi-permission-system-per-coworker]].
  @tlon_permissions %{
    "yoloMode" => true,
    "permissionReviewLog" => true,
    "permission" => %{
      "*" => "allow",
      # bash: routine runs; sudo + the catastrophic-and-never-legitimate commands are DENY (terminal,
      # so they hold even under yolo — deny is the one thing yolo can't re-permit). This deterministic
      # floor is intentionally NARROW: it is the last line, not the whole defense. The nuanced middle
      # (novel/ambiguous bash) is the manos bash-judge authorizer-link's job. See [[pi-bash-judge]].
      "bash" => %{
        "*" => "allow",
        "sudo *" => "deny",
        "rm -rf /" => "deny",
        "rm -rf /*" => "deny",
        "rm -rf --no-preserve-root*" => "deny",
        "mkfs*" => "deny",
        "dd of=/dev/*" => "deny",
        "dd if=* of=/dev/*" => "deny",
        ":(){*" => "deny",
        "chmod -R 777 /*" => "deny",
        "chown -R * /" => "deny",
        "curl * | sh" => "deny",
        "curl * | bash" => "deny",
        "wget * | sh" => "deny",
        "wget * | bash" => "deny"
      },
      "external_directory" => "allow",
      "path" => %{
        "*" => "allow",
        "*.env" => "deny",
        "*.env.*" => "deny",
        "*.env.example" => "allow",
        "*.key" => "deny",
        "*.pem" => "deny",
        "~/.aws/*" => "deny",
        "~/.ssh/*" => "deny",
        "~/.pi/agent/auth.json" => "deny"
      }
    }
  }

  # The reviewer's permission policy — @tlon_permissions with the WRITE FENCE added: the built-in
  # file-writers (`write`, `edit`) and the obvious bash-write forms are denied, so a reviewer
  # STRUCTURALLY cannot land a change (its only path is to escalate). Reads/greps/git-read fall
  # through the "*" => "allow" fallback; yoloMode keeps those from stalling on an ask. The
  # catastrophic deny-floor rides along from @tlon_permissions unchanged. See the crew contract §A.
  #
  # pi-permission-system per-tool surfaces: top-level keys are surface names; `write`/`edit` are the
  # only built-in file WRITERS (reads are read/grep/find/ls), and a per-tool deny needs no path glob.
  # Bash writes are token-gated, so we deny the common redirect/in-place forms — the airtight fence is
  # the tool deny; the bash patterns are belt-and-suspenders for the MVP (the model-judge for the
  # ambiguous middle is phase-2).
  @reviewer_permissions put_in(
                          @tlon_permissions,
                          ["permission"],
                          Map.merge(@tlon_permissions["permission"], %{
                            "write" => "deny",
                            "edit" => "deny",
                            "bash" =>
                              Map.merge(@tlon_permissions["permission"]["bash"], %{
                                "* > *" => "deny",
                                "* >> *" => "deny",
                                "sed -i*" => "deny",
                                "tee *" => "deny",
                                "dd *" => "deny"
                              })
                          })
                        )

  # The dense statusline (manos/footer) — its OWN package, not manos/pi, so dropping the funes
  # adapter doesn't take the footer with it. Added explicitly so Tlön shows it at the next cockpit
  # restart even before the flake registers it into the base config (which needs a home:switch).
  @footer_extension "#{@repo}/modules/manos/footer/src/footer.ts"

  # The machine-scope funes surface (see § "The tertius coworker" in the moduledoc for why the tools
  # are cut this way). Base tool set; `@tertius_funes_mcp` adds the cross-leaf read on top.
  @tlon_funes_mcp %{
    "funes" => %{
      "url" => "${FUNES_MCP_URL}",
      "headers" => %{"Authorization" => "!#{@repo}/scripts/funes-cli.sh bearer"},
      "directTools" => [
        "post_message",
        "bank_fact",
        "raise_issue",
        "record_done",
        "record_check",
        "get_dossier",
        "propose_habit"
      ],
      "excludeTools" => ["register", "consult_peer", "open_thread", "close_thread"]
    }
  }

  # tertius's surface: the base machine-citizen tools PLUS `machine_overview`
  # (`Funes.MCP.Tool.MachineOverview`) — the cross-leaf read that separates the synthesizer from a
  # self-contained worker.
  @tertius_funes_mcp update_in(@tlon_funes_mcp, ["funes", "directTools"], &(&1 ++ ["machine_overview"]))

  # The tertius persona → `system_prompt.md` (`--append-system-prompt`). The vantage-not-worker role.
  @tertius_role """
  You are tertius-machine, the Orbis Tertius meta agent for the Tlön machine workspace — the
  "leader of leaders." Your home is the ROOT machine thread; that thread is the operator's single
  vantage over every worker ("leaf") thread. You do NOT do the leaves' work — each leaf has its own
  lead. Your job is synthesis: read across the leaves and keep the root thread a current rollup —
  what is in flight, what is stalled or blocked, where leaves conflict or duplicate effort, and what
  the operator should look at next. Read the leaves with the `machine_overview` tool — it returns
  every open machine thread's brief (lead, next step, blockers, recent messages); synthesize from
  that, not from guesses. Post those briefings and flags to the root thread. Be terse and
  high-signal; a rollup nobody reads is worse than none. Stay quiet unless you are @-mentioned or
  asked to synthesize — you are the vantage, not another voice in the room.
  """

  # The reviewer persona → `system_prompt.md`. Names the write-deny explicitly so the model doesn't
  # keep retrying a denied tool — it should escalate instead. See Aleph.Crew / the crew MVP contract.
  @reviewer_role """
  You are reviewer-machine, a code REVIEWER on this funes task thread. Read the diff you are asked to
  review (use `git diff`/`git show` — you have repo READ access) and post terse, high-signal findings
  as thread messages. You do NOT ship changes: you CANNOT write files (the write/edit tools are denied
  to you, by policy — do not fight it). When a fix is warranted, post the patch and escalate it to the
  thread's leader with a single line:

      @<leader> ESCALATE apply: <unified diff or exact change>

  Then STOP and wait for the leader's verdict. If a write is denied, that is expected — never retry
  it; escalate instead. Attribute nothing to yourself that you did not actually verify. Be brief; a
  review nobody reads is worse than none.
  """

  # The one coworker profile: `tertius`, the Tlön CENTER — the Orbis Tertius meta agent
  # (`tertius-machine`, tab `tertius`), keying the tmux socket `aleph-tertius` and config dir. A
  # machine-scope funes citizen (@tertius_funes_mcp: the machine-citizen surface + the machine_overview
  # cross-leaf read), the @tertius_role persona, footer, sandbox, yolo permissions, glm-5.2 driver.
  # Genuine Claude access is the honest `hronir` window (real Claude, no pi-multi-account
  # impersonation), joined to the same root thread.
  @profiles [
    %Profile{
      name: "tertius",
      drop_extensions: [],
      add_extensions: [@footer_extension],
      mcp: @tertius_funes_mcp,
      model: %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @tertius_role
    },
    %Profile{
      name: "reviewer",
      drop_extensions: [],
      add_extensions: [@footer_extension],
      mcp: @tlon_funes_mcp,
      model: %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
      sandbox: @tlon_sandbox,
      permissions: @reviewer_permissions,
      system_prompt: @reviewer_role
    }
  ]

  # The coworker-driver ring the SETTINGS panel cycles (leader `m`) — ollama-only, no anthropic-via-pi
  # (see the moduledoc for why). Claude proper is the `hronir` window.
  @model_ring [
    %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
    %{provider: "ollama-cloud", model: "kimi-k2.7-code", thinking: "medium"},
    %{provider: "ollama-cloud", model: "deepseek-v4-pro", thinking: "high"}
  ]

  @doc """
  Look a profile up by name, or nil. The operator's runtime override (`Aleph.Config`
  `coworkers.<name>.model` — what the SETTINGS panel writes) is merged over the compiled
  `model`, so it flows everywhere the profile does: the materialised settings.json AND the
  launcher's `--model` flag, on the next coworker spawn.
  """
  @spec fetch(String.t()) :: Profile.t() | nil
  def fetch(name) do
    with %Profile{} = p <- Enum.find(@profiles, &(&1.name == name)) do
      p
      |> apply_model_override(Aleph.Config.coworker_model(name))
      |> apply_yolo_override(Aleph.Config.coworker_yolo(name))
    end
  end

  defp apply_model_override(p, nil), do: p
  defp apply_model_override(p, model), do: %{p | model: model}

  # The yolo knob rides inside the compiled permissions map, so an override only applies when the
  # profile HAS a policy — the deny-floor stays compiled-in, never operator-editable.
  defp apply_yolo_override(p, nil), do: p

  defp apply_yolo_override(%Profile{permissions: perms} = p, yolo) when is_map(perms),
    do: %{p | permissions: Map.put(perms, "yoloMode", yolo)}

  defp apply_yolo_override(p, _yolo), do: p

  @doc "The names of the coworker profiles aleph materialises — the rows the settings modal controls."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@profiles, & &1.name)

  @doc "The model ring the settings verb cycles through, Claude-first."
  @spec model_ring() :: [map()]
  def model_ring, do: @model_ring

  @doc "The ring entry after `current` (matched on provider+model), wrapping; unknown → the ring head."
  @spec next_model(map() | nil) :: map()
  def next_model(current) do
    i = Enum.find_index(@model_ring, &(&1.provider == current[:provider] and &1.model == current[:model]))

    case i do
      nil -> hd(@model_ring)
      i -> Enum.at(@model_ring, rem(i + 1, length(@model_ring)))
    end
  end

  @doc """
  Pure: profile + the base `settings.json`/`mcp.json` maps → the files the profile's config dir needs.
  Returns `%{settings: map, mcp: map, sandbox: map | nil, permissions: map | nil, system_prompt: binary | nil}`.
  """
  @spec render(Profile.t(), map(), map()) :: %{
          settings: map(),
          mcp: map(),
          sandbox: map() | nil,
          permissions: map() | nil,
          system_prompt: String.t() | nil
        }
  def render(%Profile{} = p, base_settings, base_mcp) do
    # Drop, then add on top — the add wins, so an add_extensions path survives even if it would
    # match a drop pattern. `uniq` keeps it idempotent once the flake also registers it into the base.
    exts =
      (base_settings["extensions"] || [])
      |> Enum.reject(fn e -> Enum.any?(p.drop_extensions, &String.contains?(e, &1)) end)
      |> Kernel.++(p.add_extensions)
      |> Enum.uniq()

    settings =
      base_settings
      |> Map.put("extensions", exts)
      |> apply_model(p.model)

    mcp =
      case p.mcp do
        :base -> base_mcp
        :none -> %{"mcpServers" => %{}}
        servers when is_map(servers) -> %{"mcpServers" => servers}
      end

    %{settings: settings, mcp: mcp, sandbox: p.sandbox, permissions: p.permissions, system_prompt: p.system_prompt}
  end

  defp apply_model(settings, nil), do: settings

  defp apply_model(settings, %{provider: prov, model: model, thinking: think}) do
    settings
    |> Map.put("defaultProvider", prov)
    |> Map.put("defaultModel", model)
    |> Map.put("defaultThinkingLevel", think)
  end

  @doc """
  The ficciones repo root (matches flake.nix's `repo`) — coworkers/launchers outside this
  module that need a repo-relative path (e.g. the Tlön Claude-Code window) share this, not a
  second hardcoded copy.
  """
  @spec repo() :: String.t()
  def repo, do: @repo

  @doc "The config dir a profile materialises into (its `PI_CODING_AGENT_DIR`)."
  @spec config_dir(String.t()) :: String.t()
  def config_dir(name), do: Path.join([base_dir_root(), "profiles", name])

  @doc """
  The tmux socket name a coworker's private server runs on (`tmux -L aleph-<profile>`). One
  socket per coworker keeps it structurally outside the user's default tmux server — and thus
  outside resurrect/continuum, so a torn-down coworker is never restored stale.
  """
  @spec socket(String.t()) :: String.t()
  def socket(name), do: "aleph-" <> name

  @doc "The persistence-free tmux config a coworker's server boots from (see `@coworker_tmux_conf`)."
  @spec tmux_conf() :: String.t()
  def tmux_conf, do: @coworker_tmux_conf

  @doc """
  Materialise a profile's config dir from the base `~/.pi/agent`. Reads the base settings/mcp, renders,
  writes the profile-specific files, and symlinks the shared ones. Idempotent. Returns the dir.

  `opts[:base]` / `opts[:root]` override the base config dir and the profiles root (for tests).
  """
  @spec materialise!(Profile.t(), keyword()) :: String.t()
  def materialise!(%Profile{} = p, opts \\ []) do
    base = opts[:base] || Path.join(base_dir_root(), "agent")
    root = opts[:root] || Path.join(base_dir_root(), "profiles")
    dir = Path.join(root, p.name)
    File.mkdir_p!(dir)

    base_settings = read_json(Path.join(base, "settings.json"), %{})
    base_mcp = read_json(Path.join(base, "mcp.json"), %{"mcpServers" => %{}})
    r = render(p, base_settings, base_mcp)

    write_json!(Path.join(dir, "settings.json"), r.settings)
    write_json!(Path.join(dir, "mcp.json"), r.mcp)

    if r.sandbox, do: write_json!(Path.join(dir, "sandbox.json"), r.sandbox)

    # pi-permission-system reads its "global" config from PI_CODING_AGENT_DIR and fail-closes to
    # "ask everything" when absent — so the coworker gets its OWN config in the nested extension dir.
    if r.permissions do
      pdir = Path.join(dir, "extensions/pi-permission-system")
      File.mkdir_p!(pdir)
      write_json!(Path.join(pdir, "config.json"), r.permissions)
    end

    if r.system_prompt, do: File.write!(Path.join(dir, "system_prompt.md"), r.system_prompt)
    File.write!(Path.join(dir, "tmux.conf"), @coworker_tmux_conf)

    # Shared, from the base: one credential store, one model catalog, one failover policy, one
    # keymap. The provider-failover.json symlink is what lets pi-multi-account fail this coworker's
    # Claude over to ollama.com glm — without it multi-account would write a fresh default here and
    # miss preferredModels. keybindings.json shares the base map (Ctrl+P/N → history/selector nav);
    # pi reads it from PI_CODING_AGENT_DIR, so a coworker without the symlink keeps pi's default
    # ctrl+p=model-cycle. Relink each time (idempotent). A missing base file just leaves a dangling
    # link pi ignores.
    for f <- ~w(auth.json models.json models-store.json provider-failover.json keybindings.json) do
      link = Path.join(dir, f)
      _ = File.rm(link)
      _ = File.ln_s(Path.join(base, f), link)
    end

    dir
  end

  # The pi config-dir root (honours PI_CODING_AGENT_DIR's parent so a redirected base still finds
  # profiles beside it; falls back to ~/.pi).
  defp base_dir_root do
    case System.get_env("PI_CODING_AGENT_DIR") do
      nil -> Path.expand("~/.pi")
      dir -> Path.dirname(Path.expand(dir))
    end
  end

  defp read_json(path, default) do
    with {:ok, body} <- File.read(path), {:ok, map} <- Jason.decode(body) do
      map
    else
      _ -> default
    end
  end

  defp write_json!(path, map), do: File.write!(path, Jason.encode!(map, pretty: true) <> "\n")
end
