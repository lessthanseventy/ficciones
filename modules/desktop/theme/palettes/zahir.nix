# ZAHIR: the daylight palette — the coin you cannot stop seeing; uqbar inverted for a screen
# read outdoors. Same keys as palettes/uqbar.nix (render.nix knows only the names): the ground is cream paper, body text a
# dark amber-brown, the highlights their deep ink versions, and the active thing is still
# inverse video — a dark field with cream ink. Selection inverts the same way, in violet:
# `sel` is a deep violet field here (light in uqbar) and `selInk` the cream in it. `white` is
# the max-contrast-on-ground colour (dark here). Super+Shift+P switches to it live.
#
# Hex without '#', uppercase, so each renderer adds the syntax its target wants.
rec {
  font = {
    family = "ComicShannsMono Nerd Font";
    mono = "ComicShannsMono Nerd Font Mono";
    fallback = "monospace";
    size = 11; # points — terminals, GTK, Qt. Low vision: biased up, never down.
    sizeLg = 13;
  };

  hue = {
    bg = "F5EFE0";
    ink = "FFF7DD"; # chip text — cream on the dark field
    amber = "573900"; # body text AND chrome — amber gone to ink
    chip = "573900"; # the inverse-video field: the body amber, cream ink on top
    ember = "843A00"; # active border gradient partner
    amberDim = "A48343"; # half-bright amber: inactive border, structure at low emphasis
    emberDim = "C27645";
    green = "175917"; # live / ok / occupied / charging
    moss = "365636"; # done: a green that recedes
    pink = "95145D"; # agents, the operator, attention
    pinkDim = "C0699B"; # pink receded: a locked-but-unfocused group border
    cyan = "0B556E"; # keys, labels, code
    lilac = "483E5D"; # secondary text
    violet = "593E9C"; # assistant identity, terminal blue
    sel = "4B2E7A"; # the SELECTED thing: inverse video too, but violet, so "selected" and "active" never read alike
    selInk = "FFF7DD"; # the ink inside the violet selection field
    selSoft = "D5C4EC"; # selection where we cannot set the ink (Claude Code's selectionBg): light, so dark text survives
    red = "99201A"; # alarm
    dim = "4B4230"; # inactive text
    sep = "A86A2A"; # structure: borders, rules (burnt orange)
    grey = "505050"; # italic / muted prose
    white = "1A1A1A";
    # Elevations for toolkit chrome (GTK/Qt/floorp): black stays the ground, panels lift.
    surface0 = "EDE5D2";
    surface1 = "E6DCC6";
    surface2 = "E1D5BB";
    surface3 = "D6C9AD";
    surface4 = "C9B996";
    # Amber-tinted darks: hover/pressed fields and menu grounds in Qt/kvantum.
    amberTint0 = "EFE2C4";
    amberTint1 = "E8D6AE";
    amberTint2 = "DFC88F";
    amberSoft = "6F480D"; # inactive highlight, visited link
  };

  # Semantic roles: what a surface asks for, so a re-theme is one edit here.
  role = with hue; {
    bg = bg;
    body = amber;
    key = cyan;
    meta = lilac;
    live = green;
    attention = pink;
    alarm = red;
    structure = sep;
    dim = dim;
    chipField = chip;
    chipInk = ink;
    selField = sel;
    selInk = selInk;
    borderActive = amber;
    borderActive2 = ember;
    borderInactive = amberDim;
    borderInactive2 = emberDim;
  };

  # The 16 ANSI slots for terminals, on paper: every colour its deep version; yellow IS the
  # body ink so `yellow` in a TUI reads as ordinary text; brightWhite is the darkest ink.
  ansi = with hue; {
    black = "1A1A1A";
    red = red;
    green = green;
    yellow = amber;
    blue = violet;
    magenta = pink;
    cyan = cyan;
    white = grey;
    brightBlack = dim;
    brightRed = "912923";
    brightGreen = "1A5B1A";
    brightYellow = "3B2A00"; # the ANSI contract: its own slot, not the chip field
    brightBlue = lilac;
    brightMagenta = "91225F";
    brightCyan = "19566A";
    brightWhite = white;
  };
  ansiList = with ansi; [
    black red green yellow blue magenta cyan white
    brightBlack brightRed brightGreen brightYellow brightBlue brightMagenta brightCyan brightWhite
  ];

  # Status tier (cockpit cards + shell cells) and identity tier (coworker archetypes).
  status = with hue; { working = green; blocked = red; await = pink; open = amber; done = moss; idle = dim; };
  identity = with hue; { surveyor = cyan; builder = green; reviewer = amber; planner = pink; assistant = violet; };
}
