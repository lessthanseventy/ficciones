# The generated files that live IN the repo (the shell bundles from source), keyed by repo-relative path. `mise theme:gen` writes them, `checks.palette-sync`
# fails the flake when a checked-in copy drifts, and the shell package overwrites them at
# build time so the store bundle can never disagree with palette.nix.
{ lib }:
let
  render = import ./render.nix { inherit lib; };
  palettes = import ./palettes;
  names = builtins.attrNames palettes;
  record = f: "{ " + lib.concatMapStringsSep ", " (n: "${n}: ${f palettes.${n}}") names + " }";
in
{
  "modules/desktop/shell/style/_palette.scss" = render.paletteScss;
  "modules/desktop/shell/lib/palette.ts" = render.paletteTs;
  "modules/desktop/shell/lib/themes.ts" = ''
    // generated from modules/desktop/theme/palettes/default.nix — edit THAT, never this file.
    export const THEMES = [${lib.concatMapStringsSep ", " (n: ''"${n}"'') names}] as const
    export type Theme = (typeof THEMES)[number]
    /** a light ground: GTK's colour-scheme and the toggle's icon follow it */
    export const LIGHT: Record<Theme, boolean> = ${record (p: lib.boolToString p.light)}
    /** the other half of a palette's family: what the toggle flips to */
    export const PARTNER: Record<Theme, Theme> = ${record (p: ''"${p.partner}"'')}
  '';
}
