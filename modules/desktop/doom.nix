# Doom in a terminal for the tlon office's arcade: doom-ascii (not in nixpkgs) drawing Freedoom, the
# free complete game, as coloured characters. `doom` starts episode one; the office runs it by name.
{ pkgs }:
let
  doom-ascii = pkgs.stdenv.mkDerivation {
    pname = "doom-ascii";
    version = "0.3.2";
    src = pkgs.fetchFromGitHub {
      owner = "wojciech-graj";
      repo = "doom-ascii";
      rev = "v0.3.2";
      sha256 = "1ndsm8x6465zs5apjyk8sfz8rq8ngnddb4naj591lfsr664vvdn7";
    };
    installPhase = ''
      runHook preInstall
      install -Dm755 "$(find . -type f -name doom-ascii -perm -u+x | head -n 1)" $out/bin/doom-ascii
      runHook postInstall
    '';
  };
in
pkgs.writeShellScriptBin "doom" ''
  exec ${doom-ascii}/bin/doom-ascii -iwad ${pkgs.freedoom}/share/games/doom/freedoom1.wad "$@"
''
