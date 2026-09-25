# UQBAR: the dark palette — the country that exists in a single copy of the encyclopedia, found
# by lamplight. The one palette + the one font, as data. Every themed surface on the machine — the astal
# shell, ghostty, GTK, Qt, btop, floorp, hyprland, hyprlock, lazygit, bat, fzf,
# cava, tmux — is GENERATED from this file (render.nix); nothing else carries a hex value.
# Plan doc §5b. Rule (Andrew, 2026-09-05): body text amber on black; cyan for keys/labels,
# lilac for secondary text; green/pink/red are semantic highlights; the active thing is
# inverse video — amber field, black ink; the SELECTED thing is inverse video too, but violet
# (sel/selInk), so "where I am" and "what I picked" never read alike. "Tasteful unicorn
# vomit", not monochrome. Every pair here clears WCAG AAA — `mise theme:contrast` proves it.
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
    bg = "000000";
    ink = "0A0A0A"; # chip text — dark on a bright field (never pure 0: termbox's default sentinel)
    amber = "FFB000"; # body text AND chrome
    chip = "FFB000"; # the inverse-video field: the active/current thing. IS the body amber —
    # a separate brighter yellow read as "not my amber", and black on this is already 10.7:1
    ember = "FF6E06"; # the hotter phosphor: active border partner AND the warning field
    amberDim = "7A5500"; # half-bright amber: inactive border, structure at low emphasis
    emberDim = "9E3B00";
    green = "33FF00"; # live / ok / occupied / charging
    moss = "62A562"; # done: a green that recedes
    pink = "F06CB4"; # agents, the operator, attention
    pinkDim = "9C4A76"; # pink receded: a locked-but-unfocused group border
    cyan = "33C7FF"; # keys, labels, code
    lilac = "B4A5D6"; # secondary text
    violet = "B98AFF"; # assistant identity, terminal blue
    sel = "C7B6E8"; # the SELECTED thing: inverse video too, but violet, so "selected" and "active" never read alike
    selInk = "1A0A2E"; # the ink inside the violet selection field
    selSoft = "2E0057"; # selection where we cannot set the ink (Claude Code's selectionBg): dark, so bright text survives
    red = "FF6969"; # alarm
    dim = "B8994C"; # inactive text
    sep = "B5651D"; # structure: borders, rules (burnt orange)
    grey = "C7C7C7"; # italic / muted prose
    white = "FFFFFF";
    # Elevations for toolkit chrome (GTK/Qt/floorp): black stays the ground, panels lift.
    surface0 = "0D0D0D";
    surface1 = "0E0E0E";
    surface2 = "141414";
    surface3 = "1A1A1A";
    surface4 = "2A2A2A";
    # Amber-tinted darks: hover/pressed fields and menu grounds in Qt/kvantum.
    amberTint0 = "100C00";
    amberTint1 = "1A1200";
    amberTint2 = "332800";
    amberSoft = "CC8D00"; # inactive highlight, visited link
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
    # who is speaking. Claude Code is the surface that needs this; the cockpit answers the same
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

  # The 16 ANSI slots for terminals. Yellow IS the body amber so `yellow` in a TUI reads as
  # ordinary text; blue is violet (a true blue on black is unreadable at this contrast). These are
  # a CONTRACT with terminal programs, not roles: `black` is the darkest thing available and
  # `white`/`brightWhite` the lightest, so a program writing `fg=black bg=white` is legible either
  # way round. zahir has to say that out loud; here it falls out of the ground being black.
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
    brightRed = "FF7777";
    brightGreen = "5FFF33";
    brightYellow = "FFD000"; # the ANSI contract: bright must out-shine yellow, so this is NOT the (calmer) chip field
    brightBlue = lilac;
    brightMagenta = "FF5FA5";
    brightCyan = "7FDFFF";
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
