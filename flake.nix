{
  description = "ficciones — one person's whole computer as modules, each a Borges story. funes is the first.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # pi (github.com/earendil-works/pi) — the agent harness manos plugs into. It is NOT a
      # build toolchain (those are erlang/elixir/bun in mise); it is a program the human
      # runs, so Nix owns it and it lives in the home profile. pi ships no nixpkgs package
      # and no flake, so we wrap its prebuilt, bun-compiled linux-x64 release binary. The
      # tarball is a whole tree — the ELF loads sibling node_modules (native .node addons),
      # a theme dir and a wasm blob — so we install all of it and symlink bin/pi.
      #
      # CRITICAL: a `bun build --compile` binary carries its app bundle as a trailer appended
      # AFTER the ELF, found by byte offset. patchelf AND strip both rewrite the ELF and
      # displace that trailer — after which bun no longer detects the embedded app and the
      # binary degrades to the bare bun CLI (observed: `pi` printed bun's help). So we must
      # NOT patch or strip it. On Arch (this box) the system glibc loader at /lib64 runs it
      # as-is. The eventual NixOS box has no such loader and CANNOT patchelf a bun binary —
      # it needs a wrapper that invokes the store ld-linux without touching the bytes (or
      # nix-ld). Deferred with metal (adopt Nix gradually), tracked here rather than lost.
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
    in
    {
      # Exposed as a build target so it can be verified (`nix build .#pi`) without touching
      # the system — the same way funes' package will be. home-manager consumes the same
      # derivation below.
      packages.${system}.pi = pi;

      # funes is an Elixir/OTP app; day-to-day dev runs through mise (matching the box's
      # toolchain). This shell is the reproducible equivalent: Elixir, plus sqlite3 for the
      # 2am repair path. A `mix release` package is a later step — SQLite is the truth, so
      # nothing is lost by packaging the runtime later.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.beamPackages.elixir_1_18 pkgs.sqlite ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install.
      # `home-manager switch --flake .#personalbox` applies the profile without touching the
      # OS. It carries the AI-aware env — pi the harness, plus the manos wiring that makes a
      # pi session a funes citizen — so the whole loop reproduces from this flake.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          (
            { lib, ... }:
            let
              # The live repo path — pi loads the REAL extension/skills so a dev edit is
              # picked up (not a stale store snapshot via `self`). Single-user machine: the
              # home dir already fixes this location.
              repo = "/home/andrew/projects/ficciones";
              manosExtension = "${repo}/modules/manos/pi/src/extension.ts";
              manosSkillsGlob = "${repo}/modules/manos/skills/*";

              # funes' MCP server, for pi-mcp-adapter. The ${VAR} refs are interpolated by
              # the adapter at connect time from the pane's env (Funes.MCP.Spawn.env prints
              # them). pi-scoped path (~/.pi/agent/mcp.json), so it never collides with a
              # global ~/.config/mcp/mcp.json a user might keep.
              funesMcpJson = builtins.toJSON {
                mcpServers.funes = {
                  url = "\${FUNES_MCP_URL}";
                  headers.Authorization = "Bearer \${FUNES_TOKEN}";
                  directTools = [ "post_message" "bank_fact" "raise_issue" "record_done" "get_dossier" ];
                  excludeTools = [ "register" ];
                };
              };
            in
            {
              home.username = "andrew";
              home.homeDirectory = "/home/andrew";
              home.stateVersion = "25.05";
              programs.home-manager.enable = true;

              # pi — the harness (byte-preserved bun binary, above). watchexec backs
              # scripts/watch.sh's change-triggered test runner (runs-on-change, debounce,
              # .gitignore-aware, restart-on-supersede); declared here so the next box has
              # it, not left to whatever the OS happens to ship.
              home.packages = [ pi pkgs.watchexec ];

              # funes' channel config — we own this file; pi only reads it.
              home.file.".pi/agent/mcp.json".text = funesMcpJson;

              # manos into pi's settings.json — MERGED, not owned: pi writes this file (auth,
              # model choice), so a read-only symlink would break it. jq unions our keys in
              # idempotently, seeding {} if absent. This is the declarative install replacing
              # the hand-edit in modules/manos/AGENTS.md.
              home.activation.manosWiring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                PI_DIR="$HOME/.pi/agent"
                SETTINGS="$PI_DIR/settings.json"
                run mkdir -p "$PI_DIR"
                [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
                run ${pkgs.jq}/bin/jq \
                  --arg ext "${manosExtension}" \
                  --arg skills "${manosSkillsGlob}" \
                  '.extensions = ((.extensions // []) + [$ext] | unique)
                   | .skills = ((.skills // []) + [$skills] | unique)
                   | .packages = ((.packages // []) + ["pi-mcp-adapter"] | unique)' \
                  "$SETTINGS" > "$SETTINGS.tmp" && run mv "$SETTINGS.tmp" "$SETTINGS"
              '';
            }
          )
        ];
      };
    };
}
