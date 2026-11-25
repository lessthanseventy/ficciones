# meatcheck, which arena's look-at-the-diff check runs: not in nixpkgs, and upstream tags no release.
{ pkgs, ... }:

let
  meatcheck = pkgs.buildGoModule {
    pname = "meatcheck";
    version = "0-unstable-2026-11-24";
    src = pkgs.fetchFromGitHub {
      owner = "jfyne";
      repo = "meatcheck";
      rev = "85cf94c7bb981cea401de3f3c23746ebc7b4e6cb";
      hash = "sha256-yM1XuFC/cBytuYDt2TqRJW/CMuFE275mlQ49woPA2k0=";
    };
    vendorHash = "sha256-xa7awD3vlzU1cATyRUY/utYS6hEU1AKDVXEEZHevHUc=";
    # TestDetectGitContextInGitRepo needs a git checkout, which the build sandbox lacks
    doCheck = false;
    meta.mainProgram = "meatcheck";
  };
in
{
  home.packages = [ meatcheck ];
}
