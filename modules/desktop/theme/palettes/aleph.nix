# ALEPH: the dark palette — the point in the cellar that holds everything, black with all the
# light inside it. The one palette + the one font, as data. Every themed surface on the machine — the astal
# shell, Console.Style, ghostty, GTK, Qt, btop, floorp, hyprland, hyprlock, lazygit, bat, fzf,
# cava, tmux — is GENERATED from this file (render.nix); nothing else carries a hex value.
# Plan doc §5b. Rule (Andrew, 2026-09-05): body text amber on black; cyan for keys/labels,
# lilac for secondary text; green/pink/red are semantic highlights; the active thing is
# inverse video — amber field, black ink. "Tasteful unicorn vomit", not monochrome.
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
    chip = "FFD000"; # the inverse-video field (brighter than body amber so ink pops)
    ember = "FF6000"; # active border gradient partner
    amberDim = "7A5500"; # half-bright amber: inactive border, structure at low emphasis
    emberDim = "7A2E00";
    green = "33FF00"; # live / ok / occupied / charging
    moss = "5FA35F"; # done: a green that recedes
    pink = "E0218A"; # agents, the operator, attention
    cyan = "33C7FF"; # keys, labels, code
    lilac = "B4A5D6"; # secondary text
    violet = "B98AFF"; # assistant identity, terminal blue
    sel = "5B00AE"; # selection / tab field (violet)
    red = "FF5555"; # alarm
    dim = "9A803F"; # inactive text
    sep = "B5651D"; # structure: borders, rules (burnt orange)
    cream = "FFF4C2"; # selected text on the violet field
    grey = "C7C7C7"; # italic / muted prose
    white = "FFFFFF";
    # Elevations for toolkit chrome (GTK/Qt/floorp): black stays the ground, panels lift.
    surface0 = "0A0A0A";
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

  # The 16 ANSI slots for terminals. Yellow IS the body amber so `yellow` in a TUI reads as
  # ordinary text; blue is violet (a true blue on black is unreadable at this contrast).
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
    brightYellow = chip;
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
