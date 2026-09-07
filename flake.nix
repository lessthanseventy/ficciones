{
  description = "ficciones — one person's whole computer as modules, each a Borges story. server is the first.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # agenix — age-encrypted secrets, decrypted at home:switch by the box's ssh key (no runtime
    # unlock). For machine secrets a non-interactive process needs; rbw stays for interactive ones.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Astal libraries, pinned HERE — the ags flake's own astal input lags by months (it lacked
    # brightness), so ags follows ours. nixpkgs only carries ags 2.x. Design doc §1.
    astal = {
      url = "github:Aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ags = {
      url = "github:Aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.astal.follows = "astal";
    };
    # hyprexpo (sandwichfarm's fork): the expose-style workspace overview with LIVE window
    # thumbnails — a compositor plugin, so it must be built against the exact Hyprland it loads
    # into. The NixOS side runs the Hyprland this flake pins (its `hyprland` input); the Arch box
    # gets it through hyprpm instead (modules/desktop/hypr/hyprland.lua says how).
    hyprexpo.url = "github:sandwichfarm/hyprexpo";
  };

  outputs =
    { self, nixpkgs, home-manager, agenix, astal, ags, hyprexpo }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      # imported, not legacyPackages: slack is unfree (the NixOS module allows it on its own side)
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      # Hardcoded, not `self`: consumers load the REAL files so a dev edit is picked up,
      # not a stale store snapshot. Single-user machine, fixed home dir.
      repo = "/home/andrew/projects/ficciones";

      # The desktop shell (modules/desktop/shell). Built here once and handed to home-manager
      # as a special arg so the Arch profile and the NixOS VM install the identical package.
      astalShell = pkgs.callPackage ./modules/desktop/shell/package.nix {
        agsPackages = ags.packages.${system};
      };

      # pi (github.com/earendil-works/pi) — the agent harness adapters plugs into; a program
      # the human runs (not a build toolchain), so Nix owns it in the home profile. No
      # nixpkgs package/flake, so we wrap the prebuilt bun-compiled linux-x64 tarball whole
      # (ELF + sibling node_modules native addons + theme + wasm) and symlink bin/pi.
      #
      # CRITICAL: a `bun build --compile` binary appends its app bundle as a trailer AFTER
      # the ELF, found by byte offset. patchelf/strip rewrite the ELF and displace that
      # trailer, so bun stops detecting the embedded app and degrades to the bare bun CLI
      # (observed: `pi` printed bun's help) — never patch or strip it. Arch's system glibc
      # loader runs it as-is; a NixOS box has no such loader and would need a wrapper that
      # invokes the store ld-linux without touching the bytes: modules/os/default.nix enables
      # programs.nix-ld, which does exactly that (verified in the VM, 2026-09-06).
      pi = pkgs.stdenv.mkDerivation rec {
        pname = "pi-coding-agent";
        version = "0.85.1";

        src = pkgs.fetchurl {
          url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
          hash = "sha256-SU5Jj0fXTSH0CzOG9qXpIaPUlTGhacq1W72soOof4lo=";
        };

        sourceRoot = "pi";

        # Keep the bun binary byte-for-byte: no strip, no ELF rewrite, no shebang munging.
        dontStrip = true;
        dontPatchELF = true;
        dontPatchShebangs = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/libexec/pi $out/bin
          cp -r . $out/libexec/pi
          ln -s $out/libexec/pi/pi $out/bin/pi
          runHook postInstall
        '';

        meta = {
          description = "pi — the AI coding-agent harness (prebuilt bun-compiled release binary, unpatched)";
          homepage = "https://github.com/earendil-works/pi";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          mainProgram = "pi";
        };
      };

      # Expert — the Elixir LSP (expert-lsp.org, NOT elixir-ls). Not in nixpkgs, so we fetch the
      # prebuilt release binary (a self-contained burrito BEAM) and install it byte-for-byte — same
      # treatment as pi/bun above: no strip, no ELF rewrite (Arch's system glibc runs it as-is;
      # patching would break the embedded runtime). It's a bare binary, not an archive → dontUnpack.
      expert = pkgs.stdenv.mkDerivation rec {
        pname = "expert";
        version = "0.1.9";

        src = pkgs.fetchurl {
          url = "https://github.com/expert-lsp/expert/releases/download/v${version}/expert_linux_amd64";
          hash = "sha256-99WQW8PwmxKNSUHHdpYz8tEIvmN/Io7kMentE30sVWM=";
        };

        dontUnpack = true;
        dontStrip = true;
        dontPatchELF = true;
        dontPatchShebangs = true;

        installPhase = ''
          runHook preInstall
          install -Dm755 $src $out/bin/expert
          runHook postInstall
        '';

        meta = {
          description = "Expert — the Elixir language server (prebuilt burrito release binary, unpatched)";
          homepage = "https://github.com/expert-lsp/expert";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          mainProgram = "expert";
        };
      };
    in
    {
      # Exposed as a build target so it can be verified (`nix build .#pi`) without touching
      # the system — the same way server' package will be. home-manager consumes the same
      # derivation below.
      packages.${system} = {
        inherit pi expert astalShell;
        astal-shell = astalShell;
      };

      # The checked-in palette outputs (shell scss/ts, Console.Palette) must equal what
      # modules/desktop/theme/palette.nix renders — `mise theme:gen` rewrites them. Without this a
      # palette edit would ship to ghostty and GTK but leave the shell and the cockpit behind.
      checks.${system}.palette-sync =
        let
          generated = import ./modules/desktop/theme/generated.nix { inherit (pkgs) lib; };
        in
        pkgs.runCommand "palette-sync" { } (
          pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (path: text: ''
              if ! diff -u ${self}/${path} ${pkgs.writeText (baseNameOf path) text}; then
                echo "palette-sync: ${path} drifts from palette.nix — run: mise theme:gen" >&2
                exit 1
              fi
            '') generated
          )
          + "touch $out\n"
        );

      # mise owns Elixir/OTP (mise.toml pins erlang 28 + elixir 1.19.5-otp-28); this shell
      # is the 2am path — sqlite3 to open the db when nothing else is up.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.sqlite ];
      };

      # The end state: the whole machine from this flake. `vm` is the laptop's configuration
      # minus the hardware, booted under QEMU with the working tree shared in at its real path
      # (modules/os/vm.nix). `ivysaur` lands when the laptop leaves Arch.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit repo astalShell hyprexpo pi; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/os
          ./modules/os/vm.nix
        ];
      };
      # The laptop. Evaluates and builds today; installs when Andrew runs the runbook
      # (docs/plans/2026-09-05-ivysaur-nixos-migration-runbook.md).
      nixosConfigurations.ivysaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit repo astalShell hyprexpo pi; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/os
          ./modules/os/ivysaur.nix
        ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install, applied
      # without touching the OS. Carries pi + the adapters wiring that makes a pi session a
      # server citizen.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit repo astalShell; };
        modules = [
          # The Hyprland stack, symlinked back to the working tree so it stays live-editable.
          ./modules/desktop
          # agenix: decrypt age secrets at activation with the box's ssh key (identityPaths
          # defaults to ~/.ssh/id_ed25519 — ours). See the age.secrets block below.
          agenix.homeManagerModules.default
          (
            { config, lib, ... }:
            let
              adaptersExtension = "${repo}/modules/adapters/pi/src/extension.ts";
              # consult — /consult and /fresh: delegate a question to a different model
              # (e.g. a text-only model delegating a screenshot to minimax-m3) and return
              # the answer.
              consultExtension = "${repo}/modules/adapters/consult/src/extension.ts";
              # fmt — format-on-save (mix format) so `mix format --check-formatted` in the
              # gate never fails on agent-written files. No typecheck here (too heavy per-save).
              fmtExtension = "${repo}/modules/adapters/fmt/src/extension.ts";
              # lsp — LSP-backed agent tools over Expert/tsserver/nil/bash-ls/json-ls;
              # servers installed via home.packages below so the next box gets them. See
              # modules/adapters/lsp/AGENTS.md.
              lspExtension = "${repo}/modules/adapters/lsp/src/extension.ts";
              # reload — restart the pi harness in place and resume the session, so an agent
              # that edited its own tooling picks up the new code. See modules/adapters/reload.
              reloadExtension = "${repo}/modules/adapters/reload/src/extension.ts";
              # footer — a dense 2-line statusline (model, context bar, I/O, branch, statuses).
              # A generic footer, NOT a server concern, so it's its OWN package (not adapters/pi,
              # which the Tlön coworker profile drops) and loads for every pi. See modules/adapters/footer.
              footerExtension = "${repo}/modules/adapters/footer/src/footer.ts";
              adaptersSkillsGlob = "${repo}/modules/adapters/skills/*";

              # server' self-contained release (`mise run server:release`). The service below
              # runs it headless; `server:console`/`:restart` drive the same bin/server, so
              # node + cookie agree via the release's own env.sh.
              serverRel = "${repo}/modules/server/_build/prod/rel/server";

              # server' MCP server for pi-mcp-adapter. Auth header is a `!command`
              # (pi-mcp-adapter §headers): tlon-cli.sh bearer mints a FRESH token per
              # connect against TLON_MCP_URL's /mint, so it survives a restart/model
              # change/secret regen — no frozen TLON_TOKEN. pi-scoped path avoids
              # colliding with a global ~/.config/mcp/mcp.json.
              serverMcpJson = builtins.toJSON {
                mcpServers.tlon = {
                  url = "\${TLON_MCP_URL}";
                  headers.Authorization = "!${repo}/scripts/tlon-cli.sh bearer";
                  directTools = [ "post_message" "bank_fact" "raise_issue" "record_done" "get_dossier" "consult_peer" ];
                  excludeTools = [ "register" ];
                };
              };

              # pi's provider config (~/.pi/agent/models.json) — SEEDED, not owned. pi writes
              # this file when an account provider is added (a Kimi coding account did exactly
              # that), so a store symlink here loses that write on every switch and leaves a
              # models.json.backup behind. models-store.json only absorbs UI-added *models*,
              # not providers. The seed below is the starting catalog for a fresh box; once the
              # file exists pi owns it. Two OpenAI-compatible providers: ollama (local daemon, apiKey
              # "ollama" is a placeholder the daemon ignores) and ollama-cloud (apiKey
              # env-interpolated by pi as \${OLLAMA_API_KEY} so the secret never lands in
              # the nix store; cloud model ids are BARE — no ":cloud" suffix, that's only
              # for the local-daemon signin path).
              piModelsJson = builtins.toJSON {
                providers = {
                  ollama = {
                    baseUrl = "http://localhost:11434/v1";
                    api = "openai-completions";
                    apiKey = "ollama";
                    models = [ { id = "qwen3-coder"; } ];
                  };
                  "ollama-cloud" = {
                    baseUrl = "https://ollama.com/v1";
                    api = "openai-completions";
                    apiKey = "\${OLLAMA_API_KEY}";
                    models = [
                      { id = "glm-5.2"; }
                      { id = "glm-5.1"; }
                      { id = "deepseek-v4-pro"; }
                      { id = "deepseek-v4-flash"; }
                      { id = "kimi-k2.7-code"; }
                      # kimi-k3 excluded: ollama.com bills it as EXTRA usage (HTTP 402), not
                      # covered by the plan — kept out so it can't be selected by accident.
                      # minimax-m3: the one cloud model taking images (`input` declared) — the
                      # vision target for /consult (text-only models delegate screenshots here).
                      { id = "minimax-m3"; input = [ "text" "image" ]; }
                    ];
                  };
                };
              };

              # pi-multi-account's config — we own it like mcp.json (the extension only
              # READS it; it self-seeds defaults only when the file is ABSENT, so our copy wins
              # and nothing rewrites config at runtime). We keep multi-account's DEFAULT
              # provider order (anthropic-first, ollama last) rather than set providerOrder:
              # that's exactly "lean on the $100 Claude plan, fall over to ollama only when
              # Claude finally caps." Qwen/Cursor excluded (no such accounts); local ollama
              # stays in rotation as the fallback. showUsage off so it doesn't fight
              # adapters/footer's statusline — flip true if you want the per-account Claude-cap
              # readout and it doesn't clash. Claude OAuth is `/login`, the human's one-time step.
              # providerOrder is anthropic-first, ollama LAST — Claude is the driver, the flat ollama.com
              # plan is the fallback when Claude caps. preferredModels.ollama pins the fallback to
              # ollama.com's cloud glm: the `:cloud` suffix is what routes multi-account's request to
              # https://ollama.com/v1 instead of the local daemon (it discovers the ollama account from
              # auth.json's `ollama` api-key entry, NOT from models.json). glm-5.1 ahead of 5.2 (5.2 was
              # 500ing on ollama.com, 2026-08-17); both listed so it hops to 5.2 if 5.1 is unavailable.
              # The five below were left implicit (extension defaults) until this pass — made
              # explicit so a defaults change upstream can't silently retune failover behavior
              # underneath us. All five are kept AT their documented default; this is a
              # "declare the decision" pass, not a behavior change.
              #   preserveInterruptedContext — keep true: rewrites the turn that triggered a
              #     failover into a verbatim handoff record instead of dropping it, so a
              #     mid-turn Claude→ollama switch doesn't lose the reasoning/tool-call trail.
              #     Exactly the continuity this rotation exists to provide.
              #   routeCompactionToHealthyAccount — keep true: if context needs compacting
              #     while the active account is rate-limited, generate the summary on the
              #     healthy fallback instead of hanging on the dead one.
              #   autoContinue — keep true: queues a continuation prompt after a switch so a
              #     long run doesn't stall waiting for a human to notice and re-type. Matches
              #     "lean on Claude, don't babysit it" (AGENTS.md, the two-bucket routing).
              #   cooldownMs — keep the 6h default: only used when a provider gives no reset
              #     metadata of its own (Anthropic/Codex normally do). With just two real
              #     accounts in rotation (anthropic, ollama), a rare 6h miss just means staying
              #     on ollama longer, not getting stuck.
              #   maxRecheckIntervalMs — keep the 600000 (10 min) default: this is already the
              #     ceiling the docs recommend ("raise to probe less, never to trust a
              #     provider's estimate") — nothing here calls for probing less often.
              # showUsage ON (was off "so it does not fight adapters/footer"): the whole routing
              # doctrine is lean-on-Claude-until-it-caps, which needs the per-account cap
              # readout visible. If it visually fights the footer, flip back — one line.
              piFailoverJson = builtins.toJSON {
                enabled = true;
                includeQwen = false;
                includeCursor = false;
                showUsage = true;
                providerOrder = [ "anthropic" "openai-codex" "qwen" "ollama" ];
                preferredModels = { ollama = [ "glm-5.1:cloud" "glm-5.2:cloud" ]; };
                preserveInterruptedContext = true;
                routeCompactionToHealthyAccount = true;
                autoContinue = true;
                cooldownMs = 21600000;
                maxRecheckIntervalMs = 600000;
              };

              # server total-recall's knobs (design: server-total-recall). Owned like the other pi
              # config; the adapter defaults if absent.
              #   correctionDetection — a user message that reads as a correction ("don't do that",
              #     "use X instead") is proposed as a PENDING server habit to review in the Tlön panel
              #     (never auto-applied).
              #   boundaryCapture — every `captureEveryTurns` turns, and at compaction/shutdown,
              #     adapters/pi extracts durable facts from ONLY the delta since the last capture (a
              #     cheap out-of-band model call — bounded input, never the full context) and banks
              #     them DERIVED. Set false to disable all automatic fact capture.
              #   captureModel — the out-of-band extractor. deepseek-v4-flash (ollama.com cloud)
              #     by default; point at a LOCAL daemon model (e.g. qwen3-coder) to keep capture
              #     deltas off the wire entirely — they are secret-redacted before egress either
              #     way, but local means zero egress and zero cloud budget.
              piRecallJson = builtins.toJSON {
                correctionDetection = true;
                boundaryCapture = true;
                captureEveryTurns = 8;
                captureModel = "deepseek-v4-flash";
              };

              # pi's keybindings (~/.pi/agent/keybindings.json) — owned like mcp.json; pi
              # only reads it (user config, applied by `/reload`). Andrew never model-cycles, so
              # reclaim Ctrl+P/N — pi binds them to app.model.cycleForward / app.session filters
              # by default. Two contexts, both wanted ("Both"):
              #   * In the editor, Ctrl+P/N walk prompt history (readline reflex). pi's docs give
              #     this exact remap as THE way to override model-cycling in-editor without
              #     touching Ctrl+P inside selectors (keybindings.md §"TUI Editor Cursor Movement").
              #   * In a list/selector (the `/` command palette, model picker), Ctrl+P/N alias
              #     Up/Down so the same fingers move the selection. Arrows stay bound too.
              piKeybindingsJson = builtins.toJSON {
                "tui.editor.historyPrevious" = "ctrl+p";
                "tui.editor.historyNext" = "ctrl+n";
                "tui.select.up" = [ "up" "ctrl+p" ];
                "tui.select.down" = [ "down" "ctrl+n" ];
              };

              # ---- Seeded (write-once) pi plugin configs. The fable deep review found two
              # plugins silently active on baked-in defaults; these make the machine policy
              # explicit. Seeded, NOT owned as home.file symlinks: each of these files is
              # runtime-writable by its plugin (/sandbox-allow persists grants, the permission
              # TUI persists session rules, /unipi:notify-settings edits its own file), so a
              # read-only store symlink would break those flows. The seed lands only when the
              # file is absent; delete a file + home:switch to re-seed it. EXCEPT sandbox.json,
              # which is force-installed on every switch (see the activation script for why) — it
              # is still a real file, not a symlink, so /sandbox-allow can write to it; it just
              # doesn't survive a switch, and project/session grants are the supported path.

              # pi-sandbox: was ENABLED with built-in defaults (enabled=true is baked into the
              # extension even with no sandbox.json). Explicit policy instead, modeled on the
              # Tlön coworker sandbox (Console.Profiles): unix sockets + local binding so
              # adapters-lspd/tmux/agent-browser work, writes scoped to the projects tree + caches,
              # the repo host allowlist, secret files deny-listed (denyWrite is a hard block).
              piSandboxSeed = pkgs.writeText "pi-sandbox-seed.json" (builtins.toJSON {
                enabled = true;
                network = {
                  allowLocalBinding = true;
                  allowAllUnixSockets = true;
                  # Derived from real Claude + pi session history — the dev-infra hosts this machine's
                  # agents actually reach. An allowlist (not "*") stays the network fence; extend it
                  # from the transcripts when a new infra host appears. Twin of console @tlon_sandbox.
                  allowedDomains = [
                    # source control + package registries
                    "github.com"
                    "*.github.com"
                    "*.githubusercontent.com"
                    "hex.pm"
                    "*.hex.pm"
                    "hexdocs.pm"
                    "*.hexdocs.pm"
                    "registry.npmjs.org"
                    "www.npmjs.com"
                    "*.npmjs.com"
                    "crates.io"
                    "static.crates.io"
                    "index.crates.io"
                    # toolchains + system package infra
                    "*.jdx.dev"
                    "sh.rustup.rs"
                    "static.rust-lang.org"
                    "cache.nixos.org"
                    "channels.nixos.org"
                    "nixos.org"
                    # AI / agent infra
                    "anthropic.com"
                    "*.anthropic.com"
                    "claude.com"
                    "*.claude.com"
                    "claude.ai"
                    "ollama.com"
                    "*.ollama.com"
                    "registry.ollama.ai"
                    "pi.dev"
                    "modelcontextprotocol.io"
                    "*.huggingface.co"
                    # language + framework + tool docs
                    "elixirforum.com"
                    "www.phoenixframework.org"
                    "expert-lsp.org"
                    "www.typescriptlang.org"
                    "react.dev"
                    "pnpm.io"
                    "playwright.dev"
                    "ghostty.org"
                    "agent-browser.dev"
                    # docs / badges / assets / a11y
                    "img.shields.io"
                    "deepwiki.com"
                    "www.w3.org"
                    "dequeuniversity.com"
                    "fonts.googleapis.com"
                    "fonts.gstatic.com"
                    # notifications
                    "ntfy.sh"
                    "herdr.dev"
                    # andrew's own app (Phoenix LiveView)
                    "myelin.us"
                    "www.myelin.us"
                  ];
                };
                filesystem = {
                  allowWrite = [ "/home/andrew/projects" "/tmp" "$XDG_RUNTIME_DIR" "~/.pi" "~/.cache" "~/.local" ];
                  allowRead = [
                    "/home/andrew/projects"
                    "/nix/store"
                    "~/.nix-profile"
                    "~/.config"
                    "~/.local"
                    "~/.pi"
                    "~/.cache"
                  ];
                  # Keep the upstream deny-/home posture: anything in home OUTSIDE the
                  # allowRead carve-outs prompts (grantable), it does not silently pass.
                  denyRead = [ "/home" ];
                  denyWrite = [ ".env" ".env.*" "*.pem" "*.key" ];
                };
              });

              # pi-permission-system: with NO config every surface defaults to `ask` (least
              # privilege) — a wall of prompts on a single-owner box. Policy: allow by default,
              # hard path-denies on credential files (the path surface gates ALL tools + bash +
              # MCP and cannot be overridden per-tool), sudo asks. pi-sandbox above stays the
              # actual isolation layer; this layer is the credential tripwire.
              piPermissionSeed = pkgs.writeText "pi-permission-seed.json" (builtins.toJSON {
                permission = {
                  "*" = "allow";
                  path = {
                    "*" = "allow";
                    "*.env" = "deny";
                    "*.env.*" = "deny";
                    "*.env.example" = "allow";
                    "*.pem" = "deny";
                    "*.key" = "deny";
                    "~/.ssh/*" = "deny";
                    "~/.aws/*" = "deny";
                    "~/.pi/agent/auth.json" = "deny";
                  };
                  # Routine bash runs; the interactive agent ASKS on sudo (a human is here to answer).
                  # The catastrophic-and-never-legitimate commands are DENY (terminal) — a deterministic
                  # floor under the adapters bash-judge link that reviews the nuanced middle. Deliberately
                  # narrow; the judge, not this list, is the real coverage for novel commands.
                  bash = {
                    "*" = "allow";
                    "sudo *" = "ask";
                    "rm -rf /" = "deny";
                    "rm -rf /*" = "deny";
                    "rm -rf --no-preserve-root*" = "deny";
                    "mkfs*" = "deny";
                    "dd of=/dev/*" = "deny";
                    "dd if=* of=/dev/*" = "deny";
                    ":(){*" = "deny";
                    "chmod -R 777 /*" = "deny";
                    "chown -R * /" = "deny";
                    "curl * | sh" = "deny";
                    "curl * | bash" = "deny";
                    "wget * | sh" = "deny";
                    "wget * | bash" = "deny";
                  };
                  external_directory = "allow";
                };
              });

              # pi-interactive-shell: defer=true keeps its large tool schema out of every
              # system prompt until enable_interactive_shell is called — context is the scarce
              # resource on the Claude bucket. console owns coworker spawning; this tool stays
              # for vim/psql/ssh overlays.
              piInteractiveShellSeed = pkgs.writeText "pi-interactive-shell-seed.json" (builtins.toJSON {
                defer = true;
              });

              # @pi-unipi/notify: suppress native toasts while the pi window is focused (you
              # are already looking at it). Event toggles (permission_request etc.) stay with
              # /unipi:notify-settings — the plugin edits this same file.
              unipiNotifySeed = pkgs.writeText "unipi-notify-seed.json" (builtins.toJSON {
                native = {
                  enabled = true;
                  suppressWhenFocused = true;
                };
              });
            in
            {
              home.username = "andrew";
              home.homeDirectory = "/home/andrew";
              home.stateVersion = "25.05";
              programs.home-manager.enable = true;

              # tmux — flake-managed (adopted from the standalone ~/.config/tmux/tmux.conf
              # repo): mouse, extended-keys, resurrect+continuum (ANDREW's session persistence
              # — coworkers run on their own `-L console-<profile>` servers with a persistence-
              # free config, see Console.Profiles), yank, tmux-thumbs. Dropped the status-script
              # chrome (gitmux/cpu/battery) that churned alongside embedded pi. Old file backed
              # up on `home:switch` via the -b flag.
              programs.tmux = {
                enable = true;
                shortcut = "b"; # Ctrl+B prefix (console's leader is Ctrl+Space, so no clash)
                escapeTime = 10;
                baseIndex = 1;
                historyLimit = 50000;
                mouse = true;
                terminal = "tmux-256color";
                plugins = with pkgs.tmuxPlugins; [ resurrect continuum yank tmux-thumbs ];
                extraConfig = ''
                  # Extended keys so shift+enter etc. round-trip to apps under tmux (the kitty-
                  # protocol gap the worklist flagged). Apps negotiate their own encoding above this.
                  # csi-u format: pi decodes CSI-u most reliably and probes for it at startup
                  # (warns on tmux's `xterm` default). Requires tmux 3.5+; this box runs 3.7b.
                  set -s extended-keys on
                  set -g extended-keys-format csi-u
                  set -as terminal-features 'xterm*:extkeys'

                  # Vi mode for the prompt line + copy mode.
                  set -g status-keys vi
                  set -g mode-keys vi
                  bind -T copy-mode-vi v send-keys -X begin-selection
                  bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"

                  # Lean status bar — session + window tabs, NO script churn (gitmux/cpu/battery
                  # dropped). Load-bearing in Tlön: this is how the pi⇄claude windows show/click.
                  set -g status-position top
                  set -g status-interval 15
                  set -g status-left " #S "
                  set -g status-right ""
                  set -g window-status-current-format " #I #W "
                  set -g window-status-format " #I #W "
                  # Colours: the machine palette (modules/desktop/theme), never hex here —
                  # the live theme's copy, so a theme switch reaches new tmux servers
                  source-file ~/.config/ficciones/theme/tmux.conf

                  # Splits + pane nav (prefix chords — the alt- bindings dropped, they clash with
                  # terminal apps like pi/nvim and aren't worth the surface; re-add if you miss them).
                  bind | split-window -h -c "#{pane_current_path}"
                  bind - split-window -v -c "#{pane_current_path}"
                  bind h select-pane -L
                  bind j select-pane -D
                  bind k select-pane -U
                  bind l select-pane -R
                  bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

                  # Persistence is for ANDREW's tmux only. Coworkers (Tlön's pi, future ones) run on
                  # their own per-profile tmux servers (tmux -L console-<profile>, persistence-free
                  # config from Console.Profiles) and come up FRESH every rebuild — agent harnesses are
                  # deliberately NOT in @resurrect-processes: auto-relaunching an agent at restore
                  # hands it stale identity/env (the old torn-down-coworker trap) and silently burns
                  # model budget.
                  set -g @continuum-restore 'on'
                  set -g @continuum-save-interval '10'
                  set -g @resurrect-capture-pane-contents 'on'
                  set -g @resurrect-processes 'iex mix nvim vim'

                  # tmux-thumbs: hint-label copy — prefix+F fires hint labels on all visible text.
                  set -g @thumbs-key F
                '';
              };

              # rbw — Bitwarden CLI with an unlock agent, for interactive password management.
              # Config here is non-secret/declarative; master password + vault stay with Bitwarden.
              # Machine secrets (OLLAMA_API_KEY) use agenix, not rbw — rbw needs an interactive unlock,
              # wrong for a non-interactive spawn.
              programs.rbw = {
                enable = true;
                settings = {
                  email = "andrew@lessthanseventy.com";
                  # base_url = "https://vault.example.tld";  # ← self-hosted Vaultwarden goes here
                  # pinentry-qt: rbw-agent has no controlling tty, so terminal pinentries EOF; a GUI
                  # dialog sidesteps that. qt not gnome3 — this box is Hyprland/Qt, and gnome3 needs
                  # GNOME's gcr-prompter.
                  pinentry = pkgs.pinentry-qt;
                  lock_timeout = 3600;
                };
              };

              # pi (byte-preserved bun binary, above). watchexec backs scripts/watch.sh's
              # change-triggered test runner. LSP servers for adapters/lsp
              # (hover/definition/references/diagnostics as pi tools) — ALL flake-managed now so
              # the next box gets them, including Expert (the Elixir LSP, expert-lsp.org — NOT
              # elixir-ls; the `expert` derivation above fetches its release binary since it's not
              # in nixpkgs). The adapter registry in modules/adapters/lspd/src/adapters.ts spawns these
              # by name — adding a language is an adapter object + usually a package here.
              home.packages = [
                pi
                expert
                pkgs.watchexec
                pkgs.typescript-language-server
                pkgs.nil
                pkgs.bash-language-server
                pkgs.vscode-json-languageserver
                # `agenix -e secrets/<name>.age` to create/edit a secret; decryption at switch is
                # handled by the agenix module (age.secrets below).
                agenix.packages.${system}.default

                # `tlon` — the product launcher (design slice F: the launcher takes the product name).
                # A thin wrapper over the mise task; not `console`, which collides with TeX Live's binary.
                (pkgs.writeShellScriptBin "tlon" ''
                  cd ${repo} || { echo "tlon: repo not found at ${repo}" >&2; exit 1; }
                  exec mise run console:run
                '')
              ];

              # age-encrypted secrets, decrypted at home:switch to $XDG_RUNTIME_DIR/agenix/<name>.
              # Gated on pathExists so the flake evaluates before the first secret is created.
              age.secrets = lib.optionalAttrs (builtins.pathExists ./secrets/ollama-api-key.age) {
                ollama-api-key.file = ./secrets/ollama-api-key.age;
              };

              # server' channel config — we own this file; pi only reads it.
              home.file.".pi/agent/mcp.json".text = serverMcpJson;

              # pi-multi-account's failover config — owned like mcp.json (see the binding
              # above for why the default anthropic-first order is left in place).
              home.file.".pi/agent/provider-failover.json".text = piFailoverJson;

              # server total-recall's noise knob (correction→habit proposals) — owned; adapter reads it.
              home.file.".pi/agent/server-recall.json".text = piRecallJson;

              # pi keybindings — owned like mcp.json (pi reads, never writes it). Reclaims
              # Ctrl+P/N from model-cycling for history + selector nav; see piKeybindingsJson.
              home.file.".pi/agent/keybindings.json".text = piKeybindingsJson;

              # adapters into pi's settings.json — MERGED, not owned: pi writes this file (auth,
              # model choice), so a read-only symlink would break it. jq unions our keys in
              # idempotently, seeding {} if absent.
              #
              # `.extensions` is PRUNE-then-add, not pure union: every path under modules/adapters/
              # is ours, so dropping every modules/adapters/ entry before re-adding the current six
              # makes a renamed/removed extension self-heal — a plain `+ [...] | unique` union
              # would leave pi loading a dead path on every subsequent home:switch.
              #
              # Defaults use `//=` (set-only-if-absent), NOT `=`: pi persists your runtime
              # model switch (Ctrl+P) back into this file, so we must not stomp it on every
              # home:switch — this only picks the default the FIRST time. defaultProvider is
              # ollama-cloud/deepseek-v4-flash: the efficient MoE default drains the short
              # rate-limit window slower than a reasoning model (glm-5.2's thinking tokens
              # trip it mid-session; `mise run ollama:usage` watches this). enabledModels is
              # the Ctrl+P cycle ring — every id from models.json.
              home.activation.manosWiring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                PI_DIR="$HOME/.pi/agent"
                SETTINGS="$PI_DIR/settings.json"
                run mkdir -p "$PI_DIR"
                [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
                run ${pkgs.jq}/bin/jq \
                  --arg ext "${adaptersExtension}" \
                  --arg ext2 "${consultExtension}" \
                  --arg ext3 "${fmtExtension}" \
                  --arg ext4 "${lspExtension}" \
                  --arg ext5 "${reloadExtension}" \
                  --arg ext6 "${footerExtension}" \
                  --arg adaptersDir "${repo}/modules/adapters/" \
                  --arg skills "${adaptersSkillsGlob}" \
                  '.extensions = (((.extensions // []) | map(select(startswith($adaptersDir) | not)))
                       + [$ext, $ext2, $ext3, $ext4, $ext5, $ext6] | unique)
                   | .skills = ((.skills // []) + [$skills] | unique)
                   # .packages is likewise PRUNE-then-add: a pure union (the old form) can add
                   # a package but never remove one, so dropping pi-cc-header from the array
                   # below did not un-install it from an already-switched machine — it just
                   # sat in settings.json forever. Strip known-retired packages by name before
                   # re-adding the current set, so retiring a package here actually retires it.
                   | .packages = (((.packages // []) | map(select(. != "npm:pi-cc-header" and . != "pi-cc-header")))
                       # pi auto-installs these npm extensions on launch. The npm: prefix
                       # matches what `pi install` persists, so `unique` dedupes against a
                       # hand-installed copy instead of doubling it.
                       #   web-search        → the Ollama search API (reuses OLLAMA_API_KEY, the
                       #                       ollama.com plan we already pay for).
                       #   agent-browser     → browser-automation tool (may want a system
                       #                       chromium — see verify note).
                       #   multi-account     → Anthropic OAuth + cap-aware failover/rotation;
                       #                       replaces pi-anthropic-auth. Config + rationale in
                       #                       provider-failover.json below. `/login` stays manual (human).
                       #   permission-system → tool-permission enforcement (pairs with sandbox).
                       #   pi-sandbox        → sandboxed bash; installed by hand, captured here.
                       #   cc-header         → Claude-Code-style startup banner + status line.
                       #   pi-research       → local deep-research (stealth browser + KB); needs
                       #                       a residential IP and a 100k-context model.
                       #   interactive-shell → real-PTY tool so pi can drive iex/psql/REPLs and
                       #                       long builds without non-interactive-tty trip-ups;
                       #                       Monitor/Hands-free modes can retire the brittle
                       #                       parts of scripts/watch.sh. Self-installs its skill;
                       #                       test it inside the console embedded pane, and note its
                       #                       spawn/PTY tools may need sandbox/permission allowlisting.
                       #   pi-retry          → zero-dep stall-watchdog + transient-error retry,
                       #                       stronger than settings.retry.enabled alone; matters
                       #                       over flaky ollama.com cloud + multi-provider failover.
                       #   notify            → "agent waiting on you" notifications (agent_settled /
                       #                       ask_user_prompt / permission_request, all default-OFF —
                       #                       enable via /unipi:notify-settings). Uses notify-send on
                       #                       Linux, so it needs a notification daemon (mako on
                       #                       Hyprland); NOT the OSC-9/777-through-ghostty path yet.
                       + ["npm:pi-mcp-adapter","npm:pi-sandbox","npm:@ollama/pi-web-search","npm:pi-agent-browser-native","npm:pi-multi-account","npm:@gotgenes/pi-permission-system","npm:@lincoln504/pi-research","npm:pi-interactive-shell","npm:@narumitw/pi-retry","npm:@pi-unipi/notify"] | unique)
                       # pi-cc-header dropped: its startup logo animation races the pi-tui
                       # first-paint (differential renderer establishes cursor/scroll state
                       # while the animation repaints above it), leaving the composer border
                       # and footer blank until a later full redraw. The extension author
                       # already guards this for reload/resume/--session launches
                       # (skipAnimation in pi-cc-header.ts) but not a plain fresh launch, and
                       # ships no setting to disable just the animation — bisected 2026-08-18.
                   | .defaultProvider //= "ollama-cloud"
                   | .defaultModel //= "deepseek-v4-flash"
                   | .defaultThinkingLevel //= "medium"
                   | .retry.enabled //= true
                   # pi-multi-account recommends zeroing the SDK per-provider retries so a capped
                   # account fails over IMMEDIATELY instead of retry-spinning before the switch.
                   # (No apostrophes in this comment: it rides inside a bash single-quoted jq string;
                   # an apostrophe would close the quote and silently truncate the program.)
                   | .retry.provider.maxRetries //= 0
                   | .enabledModels //= ["deepseek-v4-flash","glm-5.2","glm-5.1","deepseek-v4-pro","kimi-k2.7-code","minimax-m3","qwen3-coder"]' \
                  "$SETTINGS" > "$SETTINGS.tmp" && run mv "$SETTINGS.tmp" "$SETTINGS"
              '';

              # Seed the runtime-writable plugin configs (see the *Seed bindings above): install
              # only when absent, so plugin-persisted grants/settings are never stomped.
              home.activation.piPluginSeeds = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                seed() {
                  if [ ! -f "$2" ]; then
                    run mkdir -p "$(dirname "$2")"
                    run install -m 0644 "$1" "$2"
                    echo "piPluginSeeds: seeded $2"
                  fi
                }
                # sandbox.json is OWNED, not seeded — it is the one config whose absence BREAKS pi's
                # bash tool outright rather than degrading it. pi-sandbox's DEFAULT_CONFIG denies
                # /home and its allowRead is only ["." "~/.config" "~/.local" "Library"] — which does
                # NOT cover ~/.pi, where pi installs the extension's own node_modules. With a falsy
                # allowLocalBinding (also unset in the defaults) sandbox-runtime enforces bind() via
                # `vendor/seccomp/<arch>/apply-seccomp`, but that helper lives under ~/.pi, so it is
                # never bind-mounted into the namespace and exec fails ENOENT even though the binary
                # is present and fine on disk. Net: an absent file is not "unconfigured", it is
                # "configured to a profile that cannot run here" — every bash call dies with a bare
                # `apply-seccomp: No such file or directory` (127) naming nothing about sandboxing.
                # The allowRead below carries ~/.pi, which is what keeps this working. Write-once
                # seeding also let this file silently drift to a 12-domain ancestor of the list below
                # (which broke `mise` installs: sh.rustup.rs had dropped out). Grants have their own
                # homes, so stomping this one costs nothing: at a sandbox prompt choose "Allow for
                # this project" (-> ./.pi/sandbox.json, merged over this file) or session, NOT "Allow
                # for all projects" (-> here, overwritten on the next home:switch).
                force() {
                  run mkdir -p "$(dirname "$2")"
                  run install -m 0644 "$1" "$2"
                  echo "piPluginSeeds: installed (owned) $2"
                }
                force ${piSandboxSeed} "$HOME/.pi/agent/sandbox.json"
                seed ${pkgs.writeText "pi-models-seed.json" piModelsJson} "$HOME/.pi/agent/models.json"
                seed ${piPermissionSeed} "$HOME/.pi/agent/extensions/pi-permission-system/config.json"
                seed ${piInteractiveShellSeed} "$HOME/.pi/agent/interactive-shell.json"
                seed ${unipiNotifySeed} "$HOME/.unipi/config/notify/config.json"
              '';

              # The always-up sovereign channel as a headless systemd --user service. A
              # self-contained release (`mise run server:release`) means ExecStart is one
              # absolute path with no toolchain on PATH. ExecStartPre migrates first —
              # server never serves on a schema it can't repair. LOOPBACK-only. TLON_DB is PINNED
              # to the pre-rename data location (~/.local/share/funes/wb.db) so the live corpus
              # doesn't orphan — the app default is now ~/.local/share/tlon; to migrate, `mv` the
              # dir and drop the pin. Node name + cookie come from the release's own env.sh, so
              # `server:console`/`:restart` reach THIS node. Build the release before the first
              # `home:switch` that starts it.
              systemd.user.services.tlon = {
                Unit = {
                  Description = "tlon — the always-up sovereign MCP channel (loopback)";
                  Documentation = [ "file://${repo}/modules/server/AGENTS.md" ];
                  After = [ "network.target" ];
                };
                Service = {
                  Type = "exec";
                  # Worklines: artifact checks run git in the repo checkout; the memory pass +
                  # maintain monitor are on for the always-up node (both post/park, never act).
                  # The switchboard runs here too — delivery bookkeeping only until an arbiter
                  # exists.
                  Environment = [
                    "TLON_DB=/home/andrew/.local/share/funes/wb.db"
                    "TLON_START_MCP=1"
                    "TLON_START_SWITCHBOARD=1"
                    "TLON_MCP_PORT=4040"
                    "TLON_WORKLINE_ROOT=${repo}"
                    "TLON_MEMORY_PASS=1"
                    "TLON_MAINTAIN=1"
                  ];
                  # Seed + repair run at app boot (Server.Bootstrap); only the schema migration
                  # is a pre-step.
                  ExecStartPre = [
                    "${serverRel}/bin/server eval Server.Release.migrate()"
                  ];
                  ExecStart = "${serverRel}/bin/server start";
                  Restart = "on-failure";
                  RestartSec = 2;
                };
                Install.WantedBy = [ "default.target" ];
              };
            }
          )
        ];
      };
    };
}
