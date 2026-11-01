# Every palette the machine renders, by name. home-manager, the shell's stylesheets, the contrast
# gate, the manual and the shell's theme picker all read this set, so a new palette is its own file
# plus one line here.
{
  uqbar = import ./uqbar.nix;
  zahir = import ./zahir.nix;
  babel = import ./babel.nix; # light paper
  hronir = import ./hronir.nix; # dark paper
}
