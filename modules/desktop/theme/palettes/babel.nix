# BABEL: the light paper palette — a page from the library, written on by hand. Same keys as
# palettes/uqbar.nix (render.nix knows only the names): the ground is notebook paper, body text
# graphite, keys and links blue ink, and the highlights the pens in the same pencil case. The
# active thing is inverse video — a graphite field with paper ink; the selection a deep indigo
# one. `white` is the max-contrast-on-ground colour (dark here). `paper` gives floorp and Firefox
# their paper layer (render.nix): soft corners, a grain, dashed rules.
#
# Hex without '#', uppercase, so each renderer adds the syntax its target wants.
rec {
  light = true;
  partner = "hronir";
  cursor = "Bibata-Original-Classic";
  paper = true;

  # Files or directories (~ expands) the shell's photo backdrop draws from while this palette
  # is live; empty falls back to the shared wallpapers directory (shell config.json).
  wallpapers = [ ];

  font = {
    family = "ComicShannsMono Nerd Font";
    mono = "ComicShannsMono Nerd Font Mono";
    fallback = "monospace";
    size = 11; # points — terminals, GTK, Qt. Low vision: biased up, never down.
    sizeLg = 13;
  };

  hue = {
    bg = "F4ECDC"; # notebook paper
    ink = "FFF9EC"; # chip text — paper on the graphite field
    amber = "2C2A33"; # body text AND chrome — graphite
    chip = "2C2A33"; # the inverse-video field: the body graphite, paper ink on top
    ember = "80300E"; # warning: rust, the red pen's warmer cousin
    amberDim = "8F806A"; # pencil: inactive border, structure at low emphasis
    emberDim = "BF8A68";
    green = "2A5419"; # live / ok — highlighter ink
    moss = "36502F"; # done: a green that recedes
    pink = "84204F"; # agents, the operator, attention — magenta pen
    pinkDim = "AC6488";
    cyan = "1D468A"; # keys, labels, code, links — the blue biro
    lilac = "463F5C"; # secondary text
    violet = "47358A"; # assistant identity, terminal blue
    sel = "3A2F70"; # the SELECTED thing: an indigo field, so "selected" and "active" never read alike
    selInk = "FFF9EC";
    selSoft = "CCD8EE"; # selection where we cannot set the ink: a pale blue highlighter
    red = "961C1C"; # alarm — the red pen
    dim = "463F35"; # inactive text
    sep = "9A7A55"; # structure: borders, rules (a brown pencil line)
    grey = "4A4A4A"; # italic / muted prose
    white = "1A1A1A";
    # Elevations for toolkit chrome: the paper darkens a step per layer, like sheets stacked.
    surface0 = "EEE5D2";
    surface1 = "E8DEC8";
    surface2 = "E2D6BD";
    surface3 = "D8CAAD";
    surface4 = "CAB994";
    # Hover/pressed fields and menu grounds: the paper with a wash of blue ink in it.
    amberTint0 = "ECE6DA";
    amberTint1 = "E3DED3";
    amberTint2 = "D6D3CC";
    amberSoft = "4E3470"; # inactive highlight, visited link
  };

  # THE MEANING MAP — identical in every palette; see palettes/uqbar.nix for why each role exists.
  role = with hue; {
    ground = bg;
    panel = surface0;
    card = surface1;
    inputGround = surface2;
    raised = surface3;
    edge = surface4;
    hoverGround = amberTint0;
    pressedGround = amberTint1;
    menuGround = amberTint2;

    body = amber;
    key = cyan;
    meta = lilac;
    prose = grey;
    inactive = dim;
    visited = amberSoft;
    maxContrast = white;

    live = green;
    done = moss;
    attention = pink;
    attentionDim = pinkDim;
    alarm = red;
    assistant = violet;
    warn = ember;
    userVoice = green;
    assistantVoice = amber;

    cursorField = chip;
    selField = sel;
    selInk = selInk;
    selSoft = selSoft;
    accentField = cyan;
    warnField = ember;
    liveField = green;
    alarmField = red;
    attentionField = pink;
    fieldInk = ink;

    structure = sep;
    borderActive = amber;
    borderActive2 = cyan; # graphite into blue ink
    borderInactive = amberDim;
    borderInactive2 = emberDim;
  };

  # The 16 ANSI slots: the contract in palettes/zahir.nix — `black` the darkest thing available,
  # `white`/`brightWhite` the lightest, whatever the hues are called.
  ansi = with hue; {
    black = "1A1A1A";
    red = red;
    green = green;
    yellow = amber;
    blue = cyan;
    magenta = pink;
    cyan = "1B5A66";
    white = "E6DDCA"; # the paper, not the ink
    brightBlack = dim;
    brightRed = "8A2222";
    brightGreen = "2E5C1F";
    brightYellow = "3D3020";
    brightBlue = violet;
    brightMagenta = "82285A";
    brightCyan = "1F5C6B";
    brightWhite = "FFFBF2";
  };
  ansiList = with ansi; [
    black red green yellow blue magenta cyan white
    brightBlack brightRed brightGreen brightYellow brightBlue brightMagenta brightCyan brightWhite
  ];

  status = with hue; { working = green; blocked = red; await = pink; open = amber; done = moss; idle = dim; };
  identity = with hue; { surveyor = cyan; builder = green; reviewer = amber; planner = pink; assistant = violet; };
}
