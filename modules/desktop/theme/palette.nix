# The BUILD-TIME palette: `current` names a file in palettes/ — aleph (the dark one: the point
# that holds everything) or zahir (the light one: the coin you cannot stop seeing). It decides
# the checked-in generated files (the shell's default stylesheet, Console.Palette). The LIVE
# theme is a runtime choice: home-manager renders both, ~/.config/ficciones/theme points at one,
# `astal-shell theme` (Super+Shift+P) repoints it. `current` is tracked so the flake sees it.
let
  name = builtins.replaceStrings [ "\n" " " ] [ "" "" ] (builtins.readFile ./current);
in
import (./palettes + "/${name}.nix")
