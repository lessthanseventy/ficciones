{
  description = "ficciones — one person's whole computer as modules, each a Borges story. funes is the first.";

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
  };

  outputs =
    { self, nixpkgs, home-manager, agenix }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # pi (github.com/earendil-works/pi) — the agent harness manos plugs into; a program
      # the human runs (not a build toolchain), so Nix owns it in the home profile. No
      # nixpkgs package/flake, so we wrap the prebuilt bun-compiled linux-x64 tarball whole
      # (ELF + sibling node_modules native addons + theme + wasm) and symlink bin/pi.
      #
      # CRITICAL: a `bun build --compile` binary appends its app bundle as a trailer AFTER
      # the ELF, found by byte offset. patchelf/strip rewrite the ELF and displace that
      # trailer, so bun stops detecting the embedded app and degrades to the bare bun CLI
      # (observed: `pi` printed bun's help) — never patch or strip it. Arch's system glibc
      # loader runs it as-is; a NixOS box has no such loader and would need a wrapper that
      # invokes the store ld-linux without touching the bytes (or nix-ld) — deferred, tracked here.
      pi = pkgs.stdenv.mkDerivation rec {
        pname = "pi-coding-agent";
        version = "0.84.2";

        src = pkgs.fetchurl {
          url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
          hash = "sha256-kG++eH/SJcSsYk/n69Wx1Vpg4PXH71F5XSMVZPnuHBM=";
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
        version = "0.1.8";

        src = pkgs.fetchurl {
          url = "https://github.com/expert-lsp/expert/releases/download/v${version}/expert_linux_amd64";
          hash = "sha256-yvDe1U6D8xjP5lnirD3R8tLnGhwaPCirMpBHWVT9mu4=";
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
      # the system — the same way funes' package will be. home-manager consumes the same
      # derivation below.
      packages.${system} = {
        inherit pi expert;
      };

      # funes is Elixir/OTP; day-to-day dev runs through mise. This shell is the
      # reproducible equivalent — Elixir + sqlite3 for the 2am repair path. A `mix
      # release` package is a later step.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.beamPackages.elixir_1_18 pkgs.sqlite ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install, applied
      # without touching the OS. Carries pi + the manos wiring that makes a pi session a
      # funes citizen.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          # agenix: decrypt age secrets at activation with the box's ssh key (identityPaths
          # defaults to ~/.ssh/id_ed25519 — ours). See the age.secrets block below.
          agenix.homeManagerModules.default
          (
            { lib, ... }:
            let
              # Hardcoded, not `self`: pi loads the REAL extension/skills so a dev edit is
              # picked up, not a stale store snapshot. Single-user machine, fixed home dir.
              repo = "/home/andrew/projects/ficciones";
              manosExtension = "${repo}/modules/manos/pi/src/extension.ts";
              # consult — /consult and /fresh: delegate a question to a different model
              # (e.g. a text-only model delegating a screenshot to minimax-m3) and return
              # the answer.
              consultExtension = "${repo}/modules/manos/consult/src/extension.ts";
              # fmt — format-on-save (mix format) so `mix format --check-formatted` in the
              # gate never fails on agent-written files. No typecheck here (too heavy per-save).
              fmtExtension = "${repo}/modules/manos/fmt/src/extension.ts";
              # lsp — LSP-backed agent tools over Expert/tsserver/nil/bash-ls/json-ls;
              # servers installed via home.packages below so the next box gets them. See
              # modules/manos/lsp/AGENTS.md.
              lspExtension = "${repo}/modules/manos/lsp/src/extension.ts";
              # reload — restart the pi harness in place and resume the session, so an agent
              # that edited its own tooling picks up the new code. See modules/manos/reload.
              reloadExtension = "${repo}/modules/manos/reload/src/extension.ts";
              # footer — a dense 2-line statusline (model, context bar, I/O, branch, statuses).
              # A generic footer, NOT a funes concern, so it's its OWN package (not manos/pi,
              # which the Tlön coworker profile drops) and loads for every pi. See modules/manos/footer.
              footerExtension = "${repo}/modules/manos/footer/src/footer.ts";
              manosSkillsGlob = "${repo}/modules/manos/skills/*";

              # funes' self-contained release (`mise run funes:release`). The service below
              # runs it headless; `funes:console`/`:restart` drive the same bin/funes, so
              # node + cookie agree via the release's own env.sh.
              funesRel = "${repo}/modules/funes/_build/prod/rel/funes";

              # funes' MCP server for pi-mcp-adapter. Auth header is a `!command`
              # (pi-mcp-adapter §headers): funes-cli.sh bearer mints a FRESH token per
              # connect against FUNES_MCP_URL's /mint, so it survives a restart/model
              # change/secret regen — no frozen FUNES_TOKEN. pi-scoped path avoids
              # colliding with a global ~/.config/mcp/mcp.json.
              funesMcpJson = builtins.toJSON {
                mcpServers.funes = {
                  url = "\${FUNES_MCP_URL}";
                  headers.Authorization = "!${repo}/scripts/funes-cli.sh bearer";
                  directTools = [ "post_message" "bank_fact" "raise_issue" "record_done" "get_dossier" "consult_peer" ];
                  excludeTools = [ "register" ];
                };
              };

              # pi's provider config (~/.pi/agent/models.json) — we OWN this file like
              # mcp.json (pi's UI-added models land in a separate models-store.json
              # instead). Two OpenAI-compatible providers: ollama (local daemon, apiKey
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

              # pi-multi-account's config — we own it like models.json (the extension only
              # READS it; it self-seeds defaults only when the file is ABSENT, so our copy wins
              # and nothing rewrites config at runtime). We keep multi-account's DEFAULT
              # provider order (anthropic-first, ollama last) rather than set providerOrder:
              # that's exactly "lean on the $100 Claude plan, fall over to ollama only when
              # Claude finally caps." Qwen/Cursor excluded (no such accounts); local ollama
              # stays in rotation as the fallback. showUsage off so it doesn't fight
              # manos/footer's statusline — flip true if you want the per-account Claude-cap
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
              #     "lean on Claude, don't babysit it" — see [[claude-plan-preferred-bucket]].
              #   cooldownMs — keep the 6h default: only used when a provider gives no reset
              #     metadata of its own (Anthropic/Codex normally do). With just two real
              #     accounts in rotation (anthropic, ollama), a rare 6h miss just means staying
              #     on ollama longer, not getting stuck.
              #   maxRecheckIntervalMs — keep the 600000 (10 min) default: this is already the
              #     ceiling the docs recommend ("raise to probe less, never to trust a
              #     provider's estimate") — nothing here calls for probing less often.
              # showUsage ON (was off "so it does not fight manos/footer"): the whole routing
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

              # funes total-recall's knobs (design: funes-total-recall). Owned like the other pi
              # config; the adapter defaults if absent.
              #   correctionDetection — a user message that reads as a correction ("don't do that",
              #     "use X instead") is proposed as a PENDING funes habit to review in the Tlön panel
              #     (never auto-applied).
              #   boundaryCapture — every `captureEveryTurns` turns, and at compaction/shutdown,
              #     manos/pi extracts durable facts from ONLY the delta since the last capture (a
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

              # ---- Seeded (write-once) pi plugin configs. The fable deep review found two
              # plugins silently active on baked-in defaults; these make the machine policy
              # explicit. Seeded, NOT owned as home.file symlinks: each of these files is
              # runtime-writable by its plugin (/sandbox-allow persists grants, the permission
              # TUI persists session rules, /unipi:notify-settings edits its own file), so a
              # read-only store symlink would break those flows. The seed lands only when the
              # file is absent; delete a file + home:switch to re-seed it.

              # pi-sandbox: was ENABLED with built-in defaults (enabled=true is baked into the
              # extension even with no sandbox.json). Explicit policy instead, modeled on the
              # Tlön coworker sandbox (Aleph.Profiles): unix sockets + local binding so
              # manos-lspd/tmux/agent-browser work, writes scoped to the projects tree + caches,
              # the repo host allowlist, secret files deny-listed (denyWrite is a hard block).
              piSandboxSeed = pkgs.writeText "pi-sandbox-seed.json" (builtins.toJSON {
                enabled = true;
                network = {
                  allowLocalBinding = true;
                  allowAllUnixSockets = true;
                  allowedDomains = [
                    "github.com"
                    "*.github.com"
                    "*.githubusercontent.com"
                    "hex.pm"
                    "*.hex.pm"
                    "registry.npmjs.org"
                    "mise.jdx.dev"
                    "ollama.com"
                    "registry.ollama.ai"
                    "cache.nixos.org"
                    "channels.nixos.org"
                    "nixos.org"
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
                  # floor under the manos bash-judge link that reviews the nuanced middle. Deliberately
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
              # resource on the Claude bucket. aleph owns coworker spawning; this tool stays
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
              # — coworkers run on their own `-L aleph-<profile>` servers with a persistence-
              # free config, see Aleph.Profiles), yank, tmux-thumbs. Dropped the status-script
              # chrome (gitmux/cpu/battery) that churned alongside embedded pi. Old file backed
              # up on `home:switch` via the -b flag.
              programs.tmux = {
                enable = true;
                shortcut = "b"; # Ctrl+B prefix (aleph's leader is Ctrl+Space, so no clash)
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
                  set -g status-style "bg=default,fg=#FFB000"
                  set -g status-left " #S "
                  set -g status-right ""
                  set -g window-status-current-style "fg=#0a0a0a,bg=#FFB000,bold"
                  set -g window-status-current-format " #I #W "
                  set -g window-status-format " #I #W "

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
                  # their own per-profile tmux servers (tmux -L aleph-<profile>, persistence-free
                  # config from Aleph.Profiles) and come up FRESH every rebuild — agent harnesses are
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
              # change-triggered test runner. LSP servers for manos/lsp
              # (hover/definition/references/diagnostics as pi tools) — ALL flake-managed now so
              # the next box gets them, including Expert (the Elixir LSP, expert-lsp.org — NOT
              # elixir-ls; the `expert` derivation above fetches its release binary since it's not
              # in nixpkgs). The adapter registry in modules/manos/lsp/src/adapters.ts spawns these
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

                # not `aleph`: collides with TeX Live's aleph binary. Thin wrapper over the mise task.
                (pkgs.writeShellScriptBin "uqbar" ''
                  cd ${repo} || { echo "uqbar: repo not found at ${repo}" >&2; exit 1; }
                  exec mise run aleph:run
                '')
              ];

              # age-encrypted secrets, decrypted at home:switch to $XDG_RUNTIME_DIR/agenix/<name>.
              # Gated on pathExists so the flake evaluates before the first secret is created.
              age.secrets = lib.optionalAttrs (builtins.pathExists ./secrets/ollama-api-key.age) {
                ollama-api-key.file = ./secrets/ollama-api-key.age;
              };

              # funes' channel config — we own this file; pi only reads it.
              home.file.".pi/agent/mcp.json".text = funesMcpJson;

              # pi's providers (ollama local + ollama.com cloud) — owned like mcp.json.
              home.file.".pi/agent/models.json".text = piModelsJson;

              # pi-multi-account's failover config — owned like models.json (see the binding
              # above for why the default anthropic-first order is left in place).
              home.file.".pi/agent/provider-failover.json".text = piFailoverJson;

              # funes total-recall's noise knob (correction→habit proposals) — owned; adapter reads it.
              home.file.".pi/agent/funes-recall.json".text = piRecallJson;

              # manos into pi's settings.json — MERGED, not owned: pi writes this file (auth,
              # model choice), so a read-only symlink would break it. jq unions our keys in
              # idempotently, seeding {} if absent.
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
                  --arg ext "${manosExtension}" \
                  --arg ext2 "${consultExtension}" \
                  --arg ext3 "${fmtExtension}" \
                  --arg ext4 "${lspExtension}" \
                  --arg ext5 "${reloadExtension}" \
                  --arg ext6 "${footerExtension}" \
                  --arg skills "${manosSkillsGlob}" \
                  '.extensions = ((.extensions // []) + [$ext, $ext2, $ext3, $ext4, $ext5, $ext6] | unique)
                   | .skills = ((.skills // []) + [$skills] | unique)
                   | .packages = ((.packages // [])
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
                       #                       test it inside the aleph embedded pane, and note its
                       #                       spawn/PTY tools may need sandbox/permission allowlisting.
                       #   pi-retry          → zero-dep stall-watchdog + transient-error retry,
                       #                       stronger than settings.retry.enabled alone; matters
                       #                       over flaky ollama.com cloud + multi-provider failover.
                       #   notify            → "agent waiting on you" notifications (agent_settled /
                       #                       ask_user_prompt / permission_request, all default-OFF —
                       #                       enable via /unipi:notify-settings). Uses notify-send on
                       #                       Linux, so it needs a notification daemon (mako on
                       #                       Hyprland); NOT the OSC-9/777-through-ghostty path yet.
                       + ["pi-mcp-adapter","npm:pi-sandbox","npm:@ollama/pi-web-search","npm:pi-agent-browser-native","npm:pi-multi-account","npm:@gotgenes/pi-permission-system","npm:pi-cc-header","npm:@lincoln504/pi-research","npm:pi-interactive-shell","npm:@narumitw/pi-retry","npm:@pi-unipi/notify"] | unique)
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
                seed ${piSandboxSeed} "$HOME/.pi/agent/sandbox.json"
                seed ${piPermissionSeed} "$HOME/.pi/agent/extensions/pi-permission-system/config.json"
                seed ${piInteractiveShellSeed} "$HOME/.pi/agent/interactive-shell.json"
                seed ${unipiNotifySeed} "$HOME/.unipi/config/notify/config.json"
              '';

              # The always-up sovereign channel as a headless systemd --user service. A
              # self-contained release (`mise run funes:release`) means ExecStart is one
              # absolute path with no toolchain on PATH. ExecStartPre migrates first —
              # funes never serves on a schema it can't repair. LOOPBACK-only, on the REAL
              # XDG db (FUNES_DB unset → ~/.local/share/funes/wb.db). Node name + cookie
              # come from the release's own env.sh, so `funes:console`/`:restart` reach
              # THIS node. Build the release before the first `home:switch` that starts it.
              systemd.user.services.funes = {
                Unit = {
                  Description = "funes — the always-up sovereign MCP channel (loopback)";
                  Documentation = [ "file://${repo}/modules/funes/AGENTS.md" ];
                  After = [ "network.target" ];
                };
                Service = {
                  Type = "exec";
                  Environment = [ "FUNES_START_MCP=1" "FUNES_MCP_PORT=4040" ];
                  ExecStartPre = "${funesRel}/bin/funes eval Funes.Release.migrate()";
                  ExecStart = "${funesRel}/bin/funes start";
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
