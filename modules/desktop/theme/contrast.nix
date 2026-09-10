# The WCAG floor, as data. Every foreground/background pair the machine actually paints,
# with the ratio it must clear — checked against BOTH palettes by `checks.palette-contrast`
# (flake.nix) and `mise theme:contrast`. Andrew has low vision: AAA (7:1) is the bar for
# text, and WCAG's 3:1 non-text floor is the bar for a band or border you must be able to
# find. A pair that cannot be raised without breaking something else carries its real
# number and a `why`, so "we know it's 5.6" is a written decision, never a silent one.
#
# `min` is the ratio the pair must clear; `fg`/`bg` are hue names in palettes/*.nix.
palette:
let
  h = palette.hue;
  AAA = 7.0; # normal-size text
  BAND = 3.0; # a field, border or rule you have to be able to locate
  # text on the ground, and on each surface it is actually painted on
  onGround = names: map (n: { label = "${n} on the ground"; fg = n; bg = "bg"; min = AAA; }) names;
  onSurface = surface: names:
    map (n: { label = "${n} on ${surface}"; fg = n; bg = surface; min = AAA; }) names;
  # inverse video: a filled field and the ink that sits in it
  field = fg: bg: { label = "${fg} on the ${bg} field"; inherit fg bg; min = AAA; };
  band = n: { label = "${n} vs the ground"; fg = n; bg = "bg"; min = BAND; };
  # ANSI names resolve through the same lookup, prefixed
  ansiPair = fg: bg: { label = "ANSI ${fg} on ${bg}"; fg = "ansi:${fg}"; bg = "ansi:${bg}"; min = AAA; };
in
{
  # every hue that carries body-weight text
  text =
    onGround [ "amber" "cyan" "lilac" "green" "pink" "red" "violet" "moss" "grey" "dim" "amberSoft" "ember" ]
    # cards, popovers, dialogs, headerbars — the two surfaces text is set on
    ++ onSurface "surface0" [ "amber" "lilac" "dim" ]
    ++ onSurface "surface1" [ "amber" "lilac" "dim" ]
    # floorp paints sidebar inputs, hovered tabs and urlbar rows on surface2
    ++ onSurface "surface2" [ "amber" ]
    ++ onSurface "amberTint1" [ "amber" ];

  # the filled fields: chip = the active/current thing, sel = the selected thing,
  # and the semantic fills GTK/Qt paint buttons with
  fields = [
    (field "ink" "chip")
    (field "selInk" "sel")
    (field "ink" "amber")
    (field "ink" "green")
    (field "ink" "red")
    (field "ink" "pink")
    (field "ink" "cyan")
  ];

  # things you must be able to find without reading them
  bands = [
    (band "chip")
    (band "sel")
    (band "sep")
    (band "amberDim")
    (band "pinkDim")
  ];

  # The one place the maths forbids AAA: `selSoft` is a background-only selection tint for
  # surfaces that keep their own text colour (Claude Code sets selectionBg and no
  # foreground). On a ground this dark, a band bright enough to see and text bright enough
  # for 7:1 cannot both exist — so the tint stays dark and the floor here is AA.
  compromises = map
    (n: {
      label = "${n} on selSoft (background-only selection)";
      fg = n;
      bg = "selSoft";
      min = 4.5;
      why = "Claude Code exposes selectionBg with no paired foreground; see the comment in contrast.nix";
    }) [ "amber" "cyan" "lilac" "green" "dim" "pink" ];

  # The ANSI 16 are a contract, not roles: whichever way round a program pairs the ends of the
  # ramp, it has to be legible. zahir bound brightWhite to the `white` HUE (which on paper is
  # dark, being "max contrast on the ground") and so made black and brightWhite the same colour.
  # Everything a program builds out of the OTHER twelve slots is caught at render time instead,
  # by ghostty's minimum-contrast.
  # Only the black<->white ends: `brightBlack` is defined by its job on the GROUND (uqbar's is a
  # dim amber, which is the point) and a program pairing it against brightWhite is joining two
  # ends that were never meant to meet — 2.73:1, and not fixable without giving up the amber.
  ansi = [
    (ansiPair "black" "white")
    (ansiPair "black" "brightWhite")
  ];

  # resolved hexes, so the checker needs nothing but this file: the hues, plus the ANSI slots
  # under an `ansi:` prefix so both resolve through one map
  hue = palette.hue // (builtins.listToAttrs
    (map (n: { name = "ansi:${n}"; value = palette.ansi.${n}; })
      (builtins.attrNames palette.ansi)));
}
