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

      # pi (github.com/earendil-works/pi) — the agent harness manos plugs into. It is
      # NOT a build toolchain (those are erlang/elixir/bun in mise); it is a program the
      # human runs, so Nix owns it and it lives in the home profile. pi ships no nixpkgs
      # package and no flake, so we wrap its prebuilt, bun-compiled release binary: pinned
      # by hash (reproducible), autoPatchelf'd for this store's glibc. The tarball is a
      # whole tree — the ELF loads sibling node_modules (native .node addons), a theme dir
      # and a wasm blob — so we install all of it and symlink bin/pi at the real binary.
      pi = pkgs.stdenv.mkDerivation rec {
        pname = "pi-coding-agent";
        version = "0.84.2";

        src = pkgs.fetchurl {
          url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
          hash = "sha256-kG++eH/SJcSsYk/n69Wx1Vpg4PXH71F5XSMVZPnuHBM=";
        };

        sourceRoot = "pi";

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [
          pkgs.stdenv.cc.cc.lib # libstdc++ / libgcc_s for the bun-compiled binary
          pkgs.zlib
        ];

        installPhase = ''
          runHook preInstall
          mkdir -p $out/libexec/pi $out/bin
          cp -r . $out/libexec/pi
          ln -s $out/libexec/pi/pi $out/bin/pi
          runHook postInstall
        '';

        meta = {
          description = "pi — the AI coding-agent harness (prebuilt release binary, autoPatchelf'd)";
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
      # OS. It carries the AI-aware env — pi today; funes returns here as a mix-release
      # package once it is packaged.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "andrew";
            home.homeDirectory = "/home/andrew";
            home.stateVersion = "25.05";
            programs.home-manager.enable = true;

            # The harness manos targets. Its config (extensions/skills/.mcp.json) is wired
            # separately — hand-installed for now (modules/manos/AGENTS.md), a home.file
            # concern when that is nix-managed.
            home.packages = [ pi ];
          }
        ];
      };
    };
}
