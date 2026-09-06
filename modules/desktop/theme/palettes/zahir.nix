# ZAHIR: the daylight palette — the coin you cannot stop seeing; uqbar inverted for a screen
# read outdoors. Same keys as palettes/uqbar.nix (render.nix knows only the names): the ground is cream paper, body text a
# dark amber-brown, the highlights their deep ink versions, and the active thing is still
# inverse video — a dark field with cream ink. `white` is the max-contrast-on-ground colour
# (dark here); `cream` is the selection ink and so dark too. Super+Shift+P switches to it live.
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
    amber = "5C3D00"; # body text AND chrome — amber gone to ink
    chip = "3B2A00"; # the inverse-video field: a dark ground the cream ink pops from
    ember = "A34700"; # active border gradient partner
    amberDim = "C9AE7A"; # half-bright amber: inactive border, structure at low emphasis
    emberDim = "D9A98A";
    green = "1F7A1F"; # live / ok / occupied / charging
    moss = "4F7F4F"; # done: a green that recedes
    pink = "B0186E"; # agents, the operator, attention
    cyan = "0E6E8E"; # keys, labels, code
    lilac = "6B5C8A"; # secondary text
    violet = "5B3FA0"; # assistant identity, terminal blue
    sel = "D9C7F0"; # selection / tab field (violet)
    red = "B3261E"; # alarm
    dim = "8A7A5A"; # inactive text
    sep = "A86A2A"; # structure: borders, rules (burnt orange)
    cream = "1A1030"; # selected text on the violet field
    grey = "5A5A5A"; # italic / muted prose
    white = "1A1A1A";
    # Elevations for toolkit chrome (GTK/Qt/floorp): black stays the ground, panels lift.
    surface0 = "EDE5D2";
    surface1 = "E6DCC6";
    surface2 = "DFD3BA";
    surface3 = "D6C9AD";
    surface4 = "C9B996";
    # Amber-tinted darks: hover/pressed fields and menu grounds in Qt/kvantum.
    amberTint0 = "EFE2C4";
    amberTint1 = "E8D6AE";
    amberTint2 = "DFC88F";
    amberSoft = "8A5A10"; # inactive highlight, visited link
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
    selInk = cream;
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
    brightRed = "D0433A";
    brightGreen = "2E9E2E";
    brightYellow = chip;
    brightBlue = lilac;
    brightMagenta = "D0348A";
    brightCyan = "2A8FB0";
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
