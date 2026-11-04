# HRONIR: the dark paper palette — the object found because it was expected; a charcoal
# sketchbook written on in chalk and coloured pencil. Same keys as palettes/uqbar.nix: the ground
# is a warm charcoal sheet, body text chalk cream, keys a blue pencil, the highlights soft pencil
# colours. The active thing is inverse video — a chalk field with charcoal ink; the selection a
# lavender one. `paper` gives floorp and Firefox their paper layer (render.nix).
#
# Hex without '#', uppercase, so each renderer adds the syntax its target wants.
rec {
  light = false;
  partner = "babel";
  cursor = "Bibata-Original-Ice";
  blurb = "chalk on a dark sketchbook";
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
    bg = "23211D"; # charcoal paper
    ink = "1C1A17"; # chip text — charcoal on the chalk field (never pure 0: termbox's sentinel)
    amber = "EDE3CC"; # body text AND chrome — chalk
    chip = "EDE3CC";
    ember = "EE9A62"; # warning: an orange pencil
    amberDim = "7D7360"; # inactive border, structure at low emphasis
    emberDim = "93603F";
    green = "A3D98F"; # live / ok
    moss = "98B991"; # done: a green that recedes
    pink = "F2A7C8"; # agents, the operator, attention
    pinkDim = "9C6C82";
    cyan = "94C6F2"; # keys, labels, code, links — the blue pencil
    lilac = "CBC2DE"; # secondary text
    violet = "BEABF2"; # assistant identity, terminal blue
    sel = "CDBDEE"; # the SELECTED thing: a lavender field, so "selected" and "active" never read alike
    selInk = "221A33";
    selSoft = "3D3554"; # selection where we cannot set the ink: dark, so the chalk survives
    red = "FF8F86"; # alarm
    dim = "CABD9F"; # inactive text
    sep = "8E7456"; # structure: borders, rules
    grey = "D0CBC1"; # italic / muted prose
    white = "FFFFFF";
    # Elevations: the sheet lightens a step per layer.
    surface0 = "292722";
    surface1 = "2E2B26";
    surface2 = "34312B";
    surface3 = "3B3831";
    surface4 = "4A463D";
    # Hover/pressed fields and menu grounds: charcoal warmed with a little chalk dust.
    amberTint0 = "2E2A22";
    amberTint1 = "373126";
    amberTint2 = "463F30";
    amberSoft = "D8C496"; # inactive highlight, visited link
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
    borderActive2 = cyan; # chalk into blue pencil
    borderInactive = amberDim;
    borderInactive2 = emberDim;
  };

  # The 16 ANSI slots: `black` the darkest thing available, `white`/`brightWhite` the lightest.
  ansi = with hue; {
    black = "1A1917";
    red = red;
    green = green;
    yellow = amber;
    blue = cyan;
    magenta = pink;
    cyan = "8FD6D0";
    white = grey;
    brightBlack = dim;
    brightRed = "FFA39B";
    brightGreen = "B8E8A6";
    brightYellow = "FFF2D6";
    brightBlue = violet;
    brightMagenta = "F7BCD6";
    brightCyan = "AEE4DF";
    brightWhite = white;
  };
  ansiList = with ansi; [
    black
    red
    green
    yellow
    blue
    magenta
    cyan
    white
    brightBlack
    brightRed
    brightGreen
    brightYellow
    brightBlue
    brightMagenta
    brightCyan
    brightWhite
  ];

  status = with hue; {
    working = green;
    blocked = red;
    await = pink;
    open = amber;
    done = moss;
    idle = dim;
  };
  identity = with hue; {
    surveyor = cyan;
    builder = green;
    reviewer = amber;
    planner = pink;
    assistant = violet;
  };
}
