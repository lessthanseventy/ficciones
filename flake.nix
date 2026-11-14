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
    # Strata — a GTK4 file manager, on trial beside Dolphin. Pinned to a release; installed on the
    # Arch profile only, and it claims neither FileManager1 nor the file-chooser portal.
    strata = {
      url = "github:lgse/strata/v1.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # tlon's office kit and rooms (office/{kit,rooms}) at its release pointer (`live`), baked into the desktop shell's bundle —
    # the shell's office draws tlon's rail room. Pinned like any input: flake:bump moves it; the
    # dev loop (shell:dev) reads the live checkout through modules/desktop/shell/office's links.
    # From GitHub so every host can lock it; tlon's release:cut pushes `live` there.
    tlon = {
      url = "github:lessthanseventy/tlon/live";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      agenix,
      astal,
      ags,
      hyprexpo,
      ...
    }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      # imported, not legacyPackages: slack is unfree (the NixOS module allows it on its own side)
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

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

      # agent-browser, on the flake's own Chromium so it needs no `agent-browser install` download.
      agentBrowser = pkgs.writeShellScriptBin "agent-browser" ''
        export AGENT_BROWSER_EXECUTABLE_PATH="''${AGENT_BROWSER_EXECUTABLE_PATH:-${pkgs.chromium}/bin/chromium}"
        exec ${pkgs.agent-browser}/bin/agent-browser "$@"
      '';

      # agent-desktop (github.com/vercel-labs/agent-desktop) is not in nixpkgs. The release binary is
      # kept unpatched like dbx's CLI, and its clipboard helper has to stay beside it.
      agentDesktop = pkgs.stdenv.mkDerivation rec {
        pname = "agent-desktop";
        version = "1.1.0";
        src = pkgs.fetchurl {
          url = "https://github.com/vercel-labs/agent-desktop/releases/download/v${version}/agent-desktop-v${version}-x86_64-unknown-linux-gnu.tar.gz";
          hash = "sha256-773PTK8QEy5P6RXbHsZDGEyUfGXgURhFrrSDlEXX6kM=";
        };
        sourceRoot = ".";
        dontStrip = true;
        dontPatchELF = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 -t $out/bin agent-desktop agent-desktop-linux-clipboard-owner
          runHook postInstall
        '';
      };

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
      dbxSeed = pkgs.writeText "dbx-seed.json" (
        builtins.toJSON {
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
        }
      );
      dbxSeedScript = pkgs.writeShellScript "dbx-seed" ''
        export PATH=${
          pkgs.lib.makeBinPath [
            pkgs.sqlite
            pkgs.jq
          ]
        }:$PATH
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
            categories = [
              "Development"
              "Database"
            ];
          })
        ];
        postBuild = ''
          contents=${
            pkgs.appimageTools.extract {
              pname = "dbx-appimage";
              version = dbxVersion;
              src = dbxAppImageSrc;
            }
          }
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
        floorp-xpi = pkgs.callPackage ./modules/desktop/theme/floorp-ext { };
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

        # a broken close shader shows only as a window that closes without burning
        burn-shader =
          let
            render = import ./modules/desktop/theme/render.nix { inherit (pkgs) lib; };
            frag = pkgs.writeText "burn-close.frag" (
              render.burnCloseGlsl (builtins.readFile ./modules/desktop/theme/templates/burn-close.glsl)
            );
          in
          pkgs.runCommand "burn-shader" { nativeBuildInputs = [ pkgs.glslang ]; } ''
            glslangValidator -S frag ${frag}
            touch $out
          '';

        # Andrew has low vision: every foreground/background pair the machine paints has a
        # declared WCAG floor in modules/desktop/theme/contrast.nix, and EVERY palette must
        # clear it — not just whichever one `current` names. The gate that refuses the next
        # washed-out selection.
        palette-contrast =
          let
            spec =
              name: palette:
              pkgs.writeText "${name}-contrast.json" (
                builtins.toJSON (import ./modules/desktop/theme/contrast.nix palette)
              );
            run = name: palette: ''
              ${pkgs.python3}/bin/python3 ${./modules/desktop/theme/contrast.py} ${name} ${spec name palette} || rc=1
            '';
          in
          # every palette is checked before it fails: one run names all of them
          pkgs.runCommand "palette-contrast" { } (
            "rc=0\n"
            + pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList run (import ./modules/desktop/theme/palettes))
            + "[ $rc = 0 ] && touch $out\n"
          );
      };

      # mise owns Elixir/OTP (mise.toml pins erlang 28 + elixir 1.19.5-otp-28); this shell
      # is the 2am path — sqlite3 to open the db when nothing else is up.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.sqlite ];
      };

      # The desktop as full NixOS, booted under QEMU with the working tree shared in at its real
      # path (modules/os/vm.nix).
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            repo
            tlonRepo
            astalShell
            hyprexpo
            dbx
            agentBrowser
            agentDesktop
            ;
          agenixPackage = agenix.packages.${system}.default;
          agenixHome = agenix.homeManagerModules.default;
          expertPackages = inputs.expert.packages;
        };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/os
          ./modules/os/vm.nix
        ];
      };
      # The work Mac: the palette's portable surfaces only (modules/mac). Named for the user so a
      # bare `home-manager switch --flake .` there picks it.
      homeConfigurations.anmoore = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        extraSpecialArgs.expertPackages = inputs.expert.packages;
        modules = [
          ./modules/mac
          ./modules/tmux.nix
          ./modules/menard-host.nix
          {
            home.username = "anmoore";
            home.homeDirectory = "/Users/anmoore";
            home.stateVersion = "25.05";
            programs.home-manager.enable = true;
          }
        ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install, applied
      # without touching the OS. Carries the tlon service and the Claude Code wiring.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit
            repo
            tlonRepo
            astalShell
            hyprexpo
            dbx
            agentBrowser
            agentDesktop
            ;
          agenixPackage = agenix.packages.${system}.default;
          expertPackages = inputs.expert.packages;
          # Arch's Postgres is the system's, not this profile's
          pgIsReady = "/usr/bin/pg_isready";
        };
        modules = [
          # The Hyprland stack, symlinked back to the working tree so it stays live-editable.
          ./modules/desktop
          ./modules/arch
          ./modules/tmux.nix
          ./modules/menard-host.nix
          # agenix: decrypt age secrets at activation with the box's ssh key (identityPaths
          # defaults to ~/.ssh/id_ed25519 — ours). modules/agents declares the secrets.
          agenix.homeManagerModules.default
          ./modules/agents
          {
            home.username = "andrew";
            home.homeDirectory = "/home/andrew";
            home.stateVersion = "25.05";
            programs.home-manager.enable = true;
            home.packages = [ inputs.strata.packages.${system}.strata ];
          }
        ];
      };
    };
}
