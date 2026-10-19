# ZAHIR: the daylight palette — the coin you cannot stop seeing; uqbar inverted for a screen
# read outdoors. Same keys as palettes/uqbar.nix (render.nix knows only the names): the ground is cream paper, body text a
# dark amber-brown, the highlights their deep ink versions, and the active thing is still
# inverse video — a dark field with cream ink. Selection inverts the same way, in violet:
# `sel` is a deep violet field here (light in uqbar) and `selInk` the cream in it. `white` is
# the max-contrast-on-ground colour (dark here). Super+Shift+P switches to it live.
#
# Hex without '#', uppercase, so each renderer adds the syntax its target wants.
rec {
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
    bg = "F5EFE0";
    ink = "FFF7DD"; # chip text — cream on the dark field
    amber = "573900"; # body text AND chrome — amber gone to ink
    chip = "573900"; # the inverse-video field: the body amber, cream ink on top
    ember = "843A00"; # the hotter phosphor: active border partner AND the warning field
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

  # THE MEANING MAP. Surfaces name a role; only this block names a colour. That is what makes two
  # surfaces that mean the same thing look the same by construction, lets uqbar and zahir be
  # provably parallel rather than parallel by hand, and is the precondition for a palette that is
  # generated rather than written — a generated palette cannot have a hue called `amber`, it can
  # only answer "what is body?". `amber` alone was serving five different jobs across 47 call
  # sites in render.nix; those are now five names.
  role = with hue; {
    # grounds, in elevation order
    ground = bg;
    panel = surface0; # headerbar, sidebar, the statusline block
    card = surface1; # card, dialog, popover, tooltip
    inputGround = surface2; # text inputs, hovered rows
    raised = surface3; # an inactive list's selected line, meter grounds
    edge = surface4; # frame shades, the outermost step
    hoverGround = amberTint0;
    pressedGround = amberTint1;
    menuGround = amberTint2;

    # text
    body = amber; # body AND ordinary chrome
    key = cyan; # keys, labels, code, links
    meta = lilac; # secondary text
    prose = grey; # italic / muted prose
    inactive = dim;
    visited = amberSoft;
    maxContrast = white; # the one colour that is maximally legible on the ground

    # what a thing IS
    live = green; # running, ok, occupied, charging
    done = moss; # finished, and receding
    attention = pink; # agents, the operator, something wants you
    attentionDim = pinkDim; # the same, receded
    alarm = red;
    assistant = violet;
    # a warning that is the same colour as body text says nothing: ember is the step between the
    # body amber and the alarm red, and was doing nothing but partnering the active border
    warn = ember;
    # who is speaking. Claude Code is the surface that needs this; the office answers the same
    # question differently (its :operator is pink), which is a disagreement worth settling.
    userVoice = green;
    assistantVoice = amber;

    # inverse video. cursorField is WHERE YOU ARE, selField is WHAT YOU PICKED, and they must
    # never read alike; selSoft is the selection where the app keeps its own text colour.
    cursorField = chip;
    selField = sel;
    selInk = selInk;
    selSoft = selSoft;
    # The toolkit accent — GTK's accent_bg_color, floorp's --retro-accent: checkboxes, switches,
    # focus rings, the button you would press. It is a thing you ACT ON, not a thing you read or a
    # place you are, so it belongs to the neon tier with the rest of the interactive vocabulary
    # (keys, labels, links) rather than being a fifth job for the body amber.
    accentField = cyan;
    warnField = ember;
    liveField = green;
    alarmField = red;
    attentionField = pink;
    fieldInk = ink; # the ink inside any of the bright fields above

    # structure
    structure = sep; # borders, rules
    borderActive = amber;
    borderActive2 = ember; # the active border is a gradient of the two
    borderInactive = amberDim;
    borderInactive2 = emberDim;
  };

  # The 16 ANSI slots for terminals, on paper: every colour its deep version; yellow IS the body
  # ink so `yellow` in a TUI reads as ordinary text. These are a CONTRACT with terminal programs,
  # not roles: `black` is the darkest thing available and `white`/`brightWhite` the lightest, so a
  # program writing `fg=black bg=white` (or the reverse) is legible. That is why they do NOT
  # follow the `white` HUE, which on paper means "max contrast on the ground" and so is dark —
  # binding brightWhite to it made black and brightWhite the SAME colour and any program pairing
  # them invisible. A program writing bare light-on-default is unreadable on any light theme;
  # ghostty's minimum-contrast catches that at render time.
  ansi = with hue; {
    black = "1A1A1A";
    red = red;
    green = green;
    yellow = amber;
    blue = violet;
    magenta = pink;
    cyan = cyan;
    white = "E8E2D4"; # the paper, not the ink
    brightBlack = dim;
    brightRed = "912923";
    brightGreen = "1A5B1A";
    brightYellow = "3B2A00"; # the ANSI contract: its own slot, not the chip field
    brightBlue = lilac;
    brightMagenta = "91225F";
    brightCyan = "19566A";
    brightWhite = "FFFBF0"; # the lightest thing available
  };
  ansiList = with ansi; [
    black red green yellow blue magenta cyan white
    brightBlack brightRed brightGreen brightYellow brightBlue brightMagenta brightCyan brightWhite
  ];

  # Status tier (office cards + shell cells) and identity tier (coworker archetypes).
  status = with hue; { working = green; blocked = red; await = pink; open = amber; done = moss; idle = dim; };
  identity = with hue; { surveyor = cyan; builder = green; reviewer = amber; planner = pink; assistant = violet; };
}
