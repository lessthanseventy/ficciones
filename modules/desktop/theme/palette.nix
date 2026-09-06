# The palette in force: `current` names a file in palettes/ (amber — the night default — or
# paper, the daylight variant). `astal-shell theme paper` writes `current`, reruns theme:gen and
# home:switch in the background, and restarts the shell; every one of the twenty surfaces
# regenerates from the one file. `current` is tracked so the flake (a git tree) sees it.
let
  name = builtins.replaceStrings [ "\n" " " ] [ "" "" ] (builtins.readFile ./current);
in
import (./palettes + "/${name}.nix")
