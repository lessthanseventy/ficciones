{
  description = "machine — one person's whole computer, as modules. funes is the first.";

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

      # funes runs its TypeScript natively on Node 24 (no build step). Packaging is
      # therefore just: put the module in the store and wrap `node` around cli.ts.
      # node_modules is git-ignored, so the flake source never includes it — funes
      # has no runtime deps to bundle.
      funes = pkgs.stdenv.mkDerivation {
        pname = "funes";
        version = "0.0.0";
        src = ./modules/funes;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/funes
          cp -r src $out/lib/funes/
          makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/funes \
            --add-flags "--no-warnings=ExperimentalWarning" \
            --add-flags "$out/lib/funes/src/cli.ts"
          runHook postInstall
        '';
        meta = {
          description = "The machine-side memory and coordination layer.";
          mainProgram = "funes";
        };
      };
    in
    {
      packages.${system} = {
        funes = funes;
        default = funes;
      };

      apps.${system} = {
        funes = {
          type = "app";
          program = "${funes}/bin/funes";
        };
        default = self.apps.${system}.funes;
      };

      # `nix develop` — the dev toolchain: Node 24, tsc for the type gate, sqlite3
      # for the 2am repair path.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nodejs_24 pkgs.typescript pkgs.sqlite ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install.
      # `home-manager switch --flake .#personalbox` installs funes into the user
      # profile without touching the OS.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "andrew";
            home.homeDirectory = "/home/andrew";
            home.stateVersion = "25.05";
            home.packages = [ funes ];
            programs.home-manager.enable = true;
          }
        ];
      };
    };
}
