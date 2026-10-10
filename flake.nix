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
    # Expert — the Elixir LSP (expert-lsp.org, NOT elixir-ls), built from main by its own flake.
    # Main, not a release: v0.1.10 stops answering once a client rejects its registerCapability,
    # which Claude Code does (expert #904, fixed by #907). Back to a release once one has #907.
    # Its nixpkgs is left its own: that is the pin it builds and is tested against.
    expert.url = "github:expert-lsp/expert";
    # tlon's office kit and rooms (office/{kit,rooms}) at its release pointer (`live`), baked into the desktop shell's bundle —
    # the shell's office draws tlon's rail room. Pinned like any input: flake:bump moves it; the
    # dev loop (shell:dev) reads the live checkout through modules/desktop/shell/office's links.
    tlon = {
      url = "git+file:///home/andrew/projects/tlon?ref=live";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, home-manager, agenix, astal, ags, hyprexpo, ... }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      # imported, not legacyPackages: slack is unfree (the NixOS module allows it on its own side)
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      # Hardcoded, not `self`: consumers load the REAL files so a dev edit is picked up,
      # not a stale store snapshot. Single-user machine, fixed home dir.
      repo = "/home/andrew/projects/ficciones";
      # tlon — its own repo: the server, the office and the Claude Code adapters. The flake
      # runs the service from its release.
      tlonRepo = "/home/andrew/projects/tlon";

      # The desktop shell (modules/desktop/shell). Built here once and handed to home-manager
      # as a special arg so the Arch profile and the NixOS VM install the identical package.
      astalShell = pkgs.callPackage ./modules/desktop/shell/package.nix {
        agsPackages = ags.packages.${system};
        tlon = inputs.tlon;
      };

      # Expert, from its flake input (above).
      expert = inputs.expert.packages.${system}.expert;

      # dbx (github.com/t8y2/dbx) — the database GUI, plus its CLI (same store, for agents).
      # Its own flake builds Tauri from source with no binary cache, so the prebuilt AppImage is
      # wrapped instead; the CLI is the prebuilt binary from its npm platform package, kept
      # unpatched (Arch's loader runs it; the VM has nix-ld).
      dbxVersion = "0.6.28";
      dbxAppImageSrc = pkgs.fetchurl {
        url = "https://github.com/t8y2/dbx/releases/download/v${dbxVersion}/DBX_${dbxVersion}_amd64.AppImage";
        hash = "sha256-p12B4dvB2Ve/tmdTak/opKWC6ziqyexkO1V8bgeX+v8=";
      };
      dbxAppImage = pkgs.appimageTools.wrapType2 {
        pname = "dbx-appimage";
        version = dbxVersion;
        src = dbxAppImageSrc;
      };
      dbxCli = pkgs.stdenv.mkDerivation rec {
        pname = "dbx-cli";
        version = "0.4.102";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/@dbx-app/cli-linux-x64-gnu/-/cli-linux-x64-gnu-${version}.tgz";
          hash = "sha256-11idXlMJA6RGrHUlBIX2zIY+kub+6tKuXeb1pseZX24=";
        };
        sourceRoot = "package";
        dontStrip = true;
        dontPatchELF = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 bin/dbx $out/bin/dbx-native
          runHook postInstall
        '';
      };
      # One data dir for the app and the CLI, seeded on every launch (create-if-absent — see
      # the script). The seed holds only what may sit in a public repo: the local Postgres
      # (trust auth as this user, so no password) and the two SQLite projects. The AI key and
      # the prod connections are read from agenix files at launch, never from the store.
      dbxDataDir = "$HOME/.local/share/dbx";
      dbxSeed = pkgs.writeText "dbx-seed.json" (builtins.toJSON {
        connections = [
          {
            id = "ficciones-local-postgres";
            name = "local postgres";
            db_type = "postgres";
            host = "127.0.0.1";
            port = 5432;
            username = "andrew";
            password = "";
            database = null;
            ssl = false;
            save_password = false;
          }
          {
            id = "ficciones-excelsior-sqlite";
            name = "excelsior (sqlite)";
            db_type = "sqlite";
            host = "/home/andrew/projects/excelsior/excelsior_dev.db";
            port = 0;
            username = "";
            password = "";
            database = null;
            ssl = false;
            save_password = false;
          }
          {
            id = "ficciones-ex-ternal-sqlite";
            name = "ex_ternal (sqlite)";
            db_type = "sqlite";
            host = "/home/andrew/projects/ex_ternal/data/ex_ternal_dev.db";
            port = 0;
            username = "";
            password = "";
            database = null;
            ssl = false;
            save_password = false;
          }
        ];
        # ollama.com over its OpenAI-compatible endpoint, bearer = the agenix ollama-api-key.
        ai = {
          id = "ficciones-ollama-cloud";
          name = "ollama.com";
          config = {
            provider = "ollama";
            auth_method = "bearer";
            endpoint = "https://ollama.com/v1";
            model = "glm-5.2";
            api_style = "completions";
          };
        };
        # agenix secret names, resolved under $XDG_RUNTIME_DIR/agenix at launch
        ai_key_secret = "ollama-api-key";
        extra_connections_secret = "dbx-connections";
      });
      dbxSeedScript = pkgs.writeShellScript "dbx-seed" ''
        export PATH=${pkgs.lib.makeBinPath [ pkgs.sqlite pkgs.jq ]}:$PATH
        export DBX_DATA_DIR="${dbxDataDir}"
        exec ${pkgs.bash}/bin/bash ${./modules/desktop/scripts/dbx-seed.sh} ${dbxSeed}
      '';
      dbx = pkgs.symlinkJoin {
        name = "dbx-${dbxVersion}";
        paths = [
          (pkgs.writeShellScriptBin "dbx-desktop" ''
            ${dbxSeedScript}
            export DBX_DATA_DIR="${dbxDataDir}"
            exec ${dbxAppImage}/bin/dbx-appimage "$@"
          '')
          (pkgs.writeShellScriptBin "dbx" ''
            export DBX_DATA_DIR="${dbxDataDir}"
            exec ${dbxCli}/bin/dbx-native "$@"
          '')
          (pkgs.makeDesktopItem {
            name = "dbx";
            exec = "dbx-desktop %u";
            icon = "dbx";
            desktopName = "DBX";
            comment = "Database GUI";
            categories = [ "Development" "Database" ];
          })
        ];
        postBuild = ''
          contents=${pkgs.appimageTools.extract { pname = "dbx-appimage"; version = dbxVersion; src = dbxAppImageSrc; }}
          for png in $contents/usr/share/icons/hicolor/*/apps/*.png; do
            size=$(basename "$(dirname "$(dirname "$png")")")
            mkdir -p $out/share/icons/hicolor/$size/apps
            cp "$png" $out/share/icons/hicolor/$size/apps/dbx.png
          done
        '';
      };
    in
    {
      # Exposed as build targets so they can be verified (`nix build .#dbx`) without touching
      # the system — the same way server' package will be. home-manager consumes the same
      # derivation below.
      packages.${system} = {
        inherit expert astalShell dbx;
        astal-shell = astalShell;
      };

      # The checked-in palette outputs (the shell's scss/ts) must equal what
      # modules/desktop/theme/palette.nix renders — `mise theme:gen` rewrites them. Without this a
      # palette edit would ship to ghostty and GTK but leave the shell behind.
      checks.${system} = {
        palette-sync =
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

        # Andrew has low vision: every foreground/background pair the machine paints has a
        # declared WCAG floor in modules/desktop/theme/contrast.nix, and BOTH palettes must
        # clear it — not just whichever one `current` names. The gate that refuses the next
        # washed-out selection.
        palette-contrast =
          let
            spec = name: pkgs.writeText "${name}-contrast.json"
              (builtins.toJSON (import ./modules/desktop/theme/contrast.nix
                (import (./modules/desktop/theme/palettes + "/${name}.nix"))));
            run = name: ''
              ${pkgs.python3}/bin/python3 ${./modules/desktop/theme/contrast.py} ${name} ${spec name}
            '';
          in
          pkgs.runCommand "palette-contrast" { } (
            pkgs.lib.concatMapStrings run [ "uqbar" "zahir" ] + "touch $out\n"
          );
      };

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
        specialArgs = { inherit repo tlonRepo astalShell hyprexpo; };
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
        specialArgs = { inherit repo tlonRepo astalShell hyprexpo; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/os
          ./modules/os/ivysaur.nix
        ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install, applied
      # without touching the OS. Carries the tlon service and the Claude Code wiring.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit repo tlonRepo astalShell; };
        modules = [
          # The Hyprland stack, symlinked back to the working tree so it stays live-editable.
          ./modules/desktop
          # agenix: decrypt age secrets at activation with the box's ssh key (identityPaths
          # defaults to ~/.ssh/id_ed25519 — ours). See the age.secrets block below.
          agenix.homeManagerModules.default
          (
            { config, lib, ... }:
            let
              # server' self-contained release, built in tlon's `.release` checkout at its release
              # pointer (tlon's `release:cut` task moves it; a merge to main deploys nothing). The
              # service below runs it headless; `server:console`/`:restart` drive the same
              # bin/server, so node + cookie agree via the release's own env.sh.
              serverRel = "${tlonRepo}/.release/server/_build/prod/rel/server";
            in
            {
              home.username = "andrew";
              home.homeDirectory = "/home/andrew";
              home.stateVersion = "25.05";
              programs.home-manager.enable = true;

              # tmux — flake-managed (adopted from the standalone ~/.config/tmux/tmux.conf
              # repo): mouse, extended-keys, resurrect+continuum (ANDREW's session persistence
              # — coworkers run on their own `-L tlon-workspace-<id>` servers with a persistence-
              # free config, see Server.Profiles), yank, tmux-thumbs. No status-script chrome
              # (gitmux/cpu/battery). Old file backed up on `home:switch` via the -b flag.
              programs.tmux = {
                enable = true;
                shortcut = "b"; # Ctrl+B prefix
                escapeTime = 10;
                baseIndex = 1;
                historyLimit = 50000;
                mouse = true;
                terminal = "tmux-256color";
                plugins = with pkgs.tmuxPlugins; [ resurrect continuum yank tmux-thumbs ];
                extraConfig = ''
                  # Extended keys so shift+enter etc. round-trip to apps under tmux (the kitty-
                  # protocol gap the worklist flagged). Apps negotiate their own encoding above this.
                  # csi-u format: the most reliably decoded encoding for the agent TUIs.
                  # Requires tmux 3.5+; this box runs 3.7b.
                  set -s extended-keys on
                  set -g extended-keys-format csi-u
                  set -as terminal-features 'xterm*:extkeys'

                  # Vi mode for the prompt line + copy mode.
                  set -g status-keys vi
                  set -g mode-keys vi
                  bind -T copy-mode-vi v send-keys -X begin-selection
                  bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"

                  # Lean status bar — session + window tabs, NO script churn (gitmux/cpu/battery
                  # dropped). Load-bearing in Tlön: this is how the coworker windows show/click.
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
                  # terminal apps like claude/nvim and aren't worth the surface; re-add if you miss them).
                  bind | split-window -h -c "#{pane_current_path}"
                  bind - split-window -v -c "#{pane_current_path}"
                  bind h select-pane -L
                  bind j select-pane -D
                  bind k select-pane -U
                  bind l select-pane -R
                  bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

                  # Persistence is for ANDREW's tmux only. Coworkers (Tlön's Claude Code seats) run on
                  # their own per-workspace tmux servers (tmux -L tlon-workspace-<id>, persistence-free
                  # config from Server.Profiles) and come up FRESH every rebuild — agent harnesses are
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

              # watchexec backs scripts/watch.sh's change-triggered test runner. LSP servers for
              # tlon's adapters/lsp (hover/definition/references/diagnostics as agent tools) — all
              # flake-managed so the next box gets them, including Expert (the Elixir LSP, expert-lsp.org — NOT
              # elixir-ls; built from its own flake input, since it's not
              # in nixpkgs). The adapter registry in tlon's adapters/lspd/src/adapters.ts spawns these
              # by name — adding a language is an adapter object + usually a package here.
              home.packages = [
                expert
                dbx
                pkgs.watchexec
                pkgs.typescript-language-server
                pkgs.nil
                pkgs.bash-language-server
                # shell lint, for agents and for bash-language-server's diagnostics
                pkgs.shellcheck
                pkgs.vscode-json-languageserver
                pkgs.marksman
                pkgs.taplo
                pkgs.yaml-language-server
                # markdown lint, for agents
                pkgs.markdownlint-cli2
                # `agenix -e secrets/<name>.age` to create/edit a secret; decryption at switch is
                # handled by the agenix module (age.secrets below).
                agenix.packages.${system}.default

                # `tlon` — the product launcher: the office TUI, a thin wrapper over its mise task.
                (pkgs.writeShellScriptBin "tlon" ''
                  cd ${tlonRepo} || { echo "tlon: repo not found at ${tlonRepo}" >&2; exit 1; }
                  exec mise --cd ${tlonRepo} run office:run -- "$@"
                '')
              ];

              # age-encrypted secrets, decrypted at home:switch to $XDG_RUNTIME_DIR/agenix/<name>.
              # Gated on pathExists so the flake evaluates before the first secret is created.
              age.secrets = lib.optionalAttrs (builtins.pathExists ./secrets/ollama-api-key.age) {
                ollama-api-key.file = ./secrets/ollama-api-key.age;
              } // lib.optionalAttrs (builtins.pathExists ./secrets/dbx-connections.age) {
                dbx-connections.file = ./secrets/dbx-connections.age;
              };

              # The four working rules (modules/agents/how-to-work.md), as Claude Code's global CLAUDE.md.
              home.file.".claude/CLAUDE.md".source = ./modules/agents/how-to-work.md;

              # the interactive shell's rc: ls and cat are eza and bat at a terminal, the plain tools
              # for anything that reads their output (an agent's Bash)
              home.file.".zshrc".source = ./modules/os/zshrc;
              # git's global ignore (~/.gitconfig's core.excludesFile): the sandboxes' phantom files too
              home.file.".gitignore".source = ./modules/os/gitignore;
              # the workflow every repo here keeps (linear history: rebase, fast-forward, stacks); git
              # reads this beside ~/.gitconfig, which stays the machine's (identity, credentials)
              home.file.".config/git/config".source = ./modules/os/gitconfig;

              # The node cookie the service and its remote shells share (rel/env.sh.eex reads it into
              # RELEASE_COOKIE; `server:console`, `server:dev` and tlon-cli.sh rpc use it): written once, 0600, never
              # rotated by a switch — a rotation would cut a running remote shell off its node.
              home.activation.tlonCookie = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                f="$HOME/.local/share/tlon/cookie"
                if [ ! -s "$f" ]; then
                  run mkdir -p "$(dirname "$f")"
                  run sh -c "umask 077; head -c 32 /dev/urandom | base64 | tr -d '/+=\n' > \"$f\""
                fi
              '';

              # The always-up sovereign channel as a headless systemd --user service. A
              # self-contained release (tlon's `server:release` task) means ExecStart is one
              # absolute path with no toolchain on PATH. ExecStartPre migrates first —
              # server never serves on a schema it can't repair. LOOPBACK-only. The store is
              # Postgres `tlon` on the local socket (one-brain piece C, 2026-09-18; the SQLite
              # corpus at ~/.local/share/funes/wb.db was copied in once with
              # `mix server.import_sqlite`). Node name + cookie come from the release's own env.sh, so
              # `server:console`/`:restart` reach THIS node. Build the release before the first
              # `home:switch` that starts it.
              # The machine seed tlon's Server.Seed applies on every boot: this box's workspaces and
              # the facts its coworkers must see (tlon's own repo holds only product knowledge).
              xdg.configFile."tlon/seed.exs".source = ./modules/agents/tlon-seed.exs;

              # The office's CPU yields to the desktop: CPU is split between cgroups before
              # processes, so each coworker scope in app.slice was a full peer of the video player.
              # tlon.service, its coworkers' tmux scopes and its redeploys all run here (tlon passes
              # --slice=tlon.slice); the quota keeps 6 of 20 threads (and the fans) free regardless.
              systemd.user.slices.tlon = {
                Unit.Description = "tlon — the office's coworkers, server and rebuilds";
                Slice = {
                  CPUWeight = 20;
                  IOWeight = 20;
                  CPUQuota = "1400%";
                };
              };

              systemd.user.services.tlon = {
                Unit = {
                  Description = "tlon — the always-up sovereign MCP channel (loopback)";
                  Documentation = [ "file://${tlonRepo}/server/AGENTS.md" ];
                  After = [ "network.target" ];
                };
                Service = {
                  Type = "exec";
                  Slice = "tlon.slice";
                  # Worklines: artifact checks run git in the repo checkout; the memory pass is
                  # on for the always-up node (the Maintain sweeps ride Oban's cron; both post/park,
                  # never act).
                  # The switchboard runs here too — delivery bookkeeping only until an arbiter
                  # exists.
                  Environment = [
                    # The service shells tmux/claude (both profile-owned) — a boot-time start
                    # inherits the manager's PATH before the session imports the profile, and the
                    # staffing pass died on `tmux: enoent` for 31 h (2026-09-23).
                    "PATH=${config.home.profileDirectory}/bin:/usr/local/bin:/usr/bin:/bin"
                    "TLON_DATABASE=tlon"
                    # one-brain D + E: the web UI on loopback :4042 (tailscale-only beyond the box) and
                    # Oban on the store (the cron drain; the sweeps follow)
                    "TLON_START_WEB=1"
                    "TLON_WEB_PORT=4042"
                    "TLON_START_OBAN=1"
                    "TLON_START_MCP=1"
                    "TLON_START_SWITCHBOARD=1"
                    "TLON_START_ATTENTION=1"
                    "TLON_MCP_PORT=4040"
                    "TLON_WORKLINE_ROOT=${repo}"
                    "TLON_MEMORY_PASS=1"
                    # the office's small talk, on the cheap ollama tier, only while an office watches
                    "TLON_BANTER=1"
                  ];
                  # Seed + repair run at app boot (Server.Bootstrap); only the schema migration
                  # is a pre-step.
                  # A --user unit cannot order itself After= the system postgresql.service, so at
                  # boot it can start before the socket accepts; wait (up to 60 s) instead of
                  # failing the migration and leaning on Restart.
                  ExecStartPre = [
                    "/bin/sh -c 'for i in $(seq 60); do /usr/bin/pg_isready -q -h /run/postgresql && exit 0; sleep 1; done; exit 1'"
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
