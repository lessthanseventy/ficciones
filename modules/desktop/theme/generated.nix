# The generated files that live IN the repo (the shell bundles from source), keyed by repo-relative path. `mise theme:gen` writes them, `checks.palette-sync`
# fails the flake when a checked-in copy drifts, and the shell package overwrites them at
# build time so the store bundle can never disagree with palette.nix.
{ lib }:
let
  render = import ./render.nix { inherit lib; };
in
{
  "modules/desktop/shell/style/_palette.scss" = render.paletteScss;
  "modules/desktop/shell/lib/palette.ts" = render.paletteTs;
}
