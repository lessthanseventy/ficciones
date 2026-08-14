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
    in
    {
      # funes is an Elixir/OTP app; day-to-day dev runs through mise (matching the
      # box's toolchain). This shell is the reproducible equivalent: Elixir, plus
      # sqlite3 for the 2am repair path. A `mix release` package is a later step —
      # SQLite is the truth, so nothing is lost by packaging the runtime later.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.beamPackages.elixir_1_18 pkgs.sqlite ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install.
      # `home-manager switch --flake .#personalbox` applies the profile without
      # touching the OS. funes returns here as a mix-release package once it's
      # packaged; for now the profile is minimal.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "andrew";
            home.homeDirectory = "/home/andrew";
            home.stateVersion = "25.05";
            programs.home-manager.enable = true;
          }
        ];
      };
    };
}
