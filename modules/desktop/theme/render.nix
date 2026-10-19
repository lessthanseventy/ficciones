# Every themed surface as a pure string function of palette.nix. No pkgs, no config: the
# home-manager module (default.nix) writes these to ~/.config, the shell package bakes the
# first two into its bundle, and flake `checks.palette-sync` diffs the checked-in copies
# against them. Add a surface = add a function here; never hand-mirror a hex value.
{ lib, palette ? import ./palette.nix }:

let
  p = palette;
  r = p.role;
  f = p.font;
  # `p.hue` is deliberately NOT bound here. A surface names a ROLE; only the palette EXPORTS
  # below — the tokens we hand to our own code, whose consumers do think in colours — bind the
  # hues, inside their own `let`. So reaching for a hue from a surface is an undefined variable,
  # which is a better gate than remembering not to.
  hex = c: "#${c}";
  low = c: lib.toLower c;
  # rgb triple for formats that want decimals
  rgb = c:
    let
      n = s: lib.fromHexString s;
    in
    "${toString (n (builtins.substring 0 2 c))}, ${toString (n (builtins.substring 2 2 c))}, ${toString (n (builtins.substring 4 2 c))}";
  gen = "generated from modules/desktop/theme/palette.nix — edit THAT, never this file";
  fontStack = ''"${f.family}", "${f.mono}", ${f.fallback}'';
  fill = template: subs: lib.replaceStrings (map (k: "@${k}@") (builtins.attrNames subs)) (map hex (builtins.attrValues subs)) template;
  # The substitution map the vendored templates (kvantum, qss, floorp) use. Role names, like
  # everything else here: a template that says @body@ keeps working when a palette calls its body
  # colour something other than amber.
  templateSubs = {
    inherit (r) ground body key live alarm inactive structure visited
      panel card inputGround raised edge hoverGround pressedGround menuGround borderInactive;
  };
in
rec {
  # ---- the palette EXPORTS -------------------------------------------------------------
  # The one place hues are named. These hand the palette to our own code (the shell's stylesheet,
  # scripts that draw), and those consumers name colours, not roles — converting
  # them means renaming every `$amber` in the shell's SCSS, which is its own pass.
  paletteScss = ''
    // ${gen}. _tokens.scss forwards this and adds the metrics.
    //
    // TWO VOCABULARIES, and the rule is: use a ROLE. Roles say what a thing MEANS, so two
    // surfaces that mean the same thing cannot drift apart, and a palette whose body colour is
    // not amber still works. There are no colour-named tokens, so a stale one is a sass error.
    //
    // The exception is the CATEGORICAL tier at the bottom: hues used because they are
    // DISTINGUISHABLE from each other (log sources, the per-card hue map), where the point is
    // that they differ, not that they mean anything.

    // grounds, in elevation order
    $ground:        ${hex r.ground};
    $panel:         ${hex r.panel};
    $card:          ${hex r.card};
    $input-ground:  ${hex r.inputGround};
    $raised:        ${hex r.raised};
    $edge:          ${hex r.edge};

    // text
    $body:          ${hex r.body};   // body text AND ordinary chrome
    $key:           ${hex r.key};    // keys, labels, code, links
    $meta:          ${hex r.meta};   // secondary text
    $prose:         ${hex r.prose};
    $inactive:      ${hex r.inactive};
    $max-contrast:  ${hex r.maxContrast};  // what hover lifts to; works on any base

    // what a thing IS
    $live:          ${hex r.live};   // running, ok, occupied
    $done:          ${hex r.done};
    $attention:     ${hex r.attention};   // agents, the operator, something wants you
    $alarm:         ${hex r.alarm};
    $assistant:     ${hex r.assistant};
    $warn:          ${hex r.warn};   // the step between the body and the alarm

    // inverse video: cursorField is WHERE YOU ARE, selField is WHAT YOU PICKED
    $cursor-field:  ${hex r.cursorField};
    $sel-field:     ${hex r.selField};
    $sel-ink:       ${hex r.selInk};
    $field-ink:     ${hex r.fieldInk};   // the ink inside any bright field
    $accent-field:  ${hex r.accentField}; // a control you act on: slider, switch, focus ring

    // structure
    $structure:     ${hex r.structure};
    $border-active:   ${hex r.borderActive};
    $border-inactive: ${hex r.borderInactive};

    // status tier (cards, cells) and identity tier (coworker archetypes)
    $st-working: ${hex p.status.working};
    $st-blocked: ${hex p.status.blocked};
    $st-await:   ${hex p.status.await};
    $st-open:    ${hex p.status.open};
    $st-done:    ${hex p.status.done};
    $st-idle:    ${hex p.status.idle};
    $arch-surveyor:  ${hex p.identity.surveyor};
    $arch-builder:   ${hex p.identity.builder};
    $arch-reviewer:  ${hex p.identity.reviewer};
    $arch-planner:   ${hex p.identity.planner};
    $arch-assistant: ${hex p.identity.assistant};

    // THE CATEGORICAL TIER — hues as categories, not as meanings. Only the log-source colours
    // and the per-card hue map may use these; anything else wants a role above.
    $cat-amber:  ${hex r.body};
    $cat-green:  ${hex r.live};
    $cat-pink:   ${hex r.attention};
    $cat-cyan:   ${hex r.key};
    $cat-lilac:  ${hex r.meta};
    $cat-violet: ${hex r.assistant};
    $cat-red:    ${hex r.alarm};

    // The one font. Low vision: sizes bias up, never down.
    $font: ${fontStack};

    // Hover/pressed fields: the body colour at low alpha, so hover reads as "lit", not recoloured.
    $hover: rgba($body, 0.12);
    $pressed: rgba($body, 0.22);
  '';

  # Roles for the shell's Cairo drawing (the office rail), which CSS cannot reach either.
  shellRoles = lib.mapAttrs (_: hex) {
    inherit (r) ground panel raised edge structure borderInactive body key meta prose inactive
      live attention alarm fieldInk;
    surveyor = p.identity.surveyor; builder = p.identity.builder; reviewer = p.identity.reviewer;
    planner = p.identity.planner; assistant = p.identity.assistant;
  };

  # The palette as JSON — the shell loads the theme's copy at runtime for its Pango markup.
  wallpapersJson = builtins.toJSON (p.wallpapers or [ ]);

  paletteJson = let h = p.hue; in builtins.toJSON {
    amber = hex h.amber; green = hex h.green; pink = hex h.pink; cyan = hex h.cyan;
    lilac = hex h.violet; chip = hex h.chip; red = hex h.red; dim = hex h.dim;
    role = shellRoles;
  };

  paletteTs = let h = p.hue; in ''
    // ${gen}. The palette as JS, for the one place CSS cannot reach: Pango markup in a label.
    export const PALETTE = {
      amber: "${hex h.amber}",
      green: "${hex h.green}",
      pink: "${hex h.pink}",
      cyan: "${hex h.cyan}",
      lilac: "${hex h.violet}",
      chip: "${hex h.chip}",
      red: "${hex h.red}",
      dim: "${hex h.dim}",
    } as const
    export type Hue = keyof typeof PALETTE
    export const HUES: Hue[] = ["amber", "green", "pink", "cyan", "lilac"]
    /** roles (and coworker archetypes) for Cairo drawing; the live theme swaps them in place */
    export const ROLE = {
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "  ${k}: \"${v}\",\n") shellRoles)}} as const
    export type Role = keyof typeof ROLE
  '';

  # ---- Neovim (asterion): the palette as a Lua table --------------------------------------
  # asterion reads ~/.config/ficciones/theme/nvim-palette.lua at startup and names ROLES; the
  # base16 slots feed base16-nvim for syntax. Syntax hues are a CATEGORY tier (like the shell's
  # `$cat-*`): code needs more distinct colours than the roles carry, so those slots bind hues
  # directly, on purpose, here and nowhere in the editor.
  nvimPalette = { name, light }:
    let
      h = p.hue;
      row = attrs: lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "    ${k} = \"${hex v}\",") attrs);
      base16 = {
        base00 = r.ground; base01 = r.panel; base02 = r.raised; base03 = r.inactive;
        base04 = r.meta; base05 = r.body; base06 = r.prose; base07 = r.maxContrast;
        # syntax: variables · numbers · types · strings · regex/support · functions · keywords · deprecated
        base08 = h.lilac; base09 = h.ember; base0A = h.amberSoft; base0B = h.green;
        base0C = h.cyan; base0D = h.violet; base0E = h.pink; base0F = h.sep;
      };
    in ''
      -- ${gen}
      return {
        name = "${name}",
        light = ${lib.boolToString light},
        font = { family = "${f.family}", size = ${toString f.size} },
        role = {
      ${row r}
        },
        ansi = {
      ${row p.ansi}
        },
        base16 = {
      ${row base16}
        },
      }
    '';

  # ---- The web UI (Server.Web, one-brain piece D): the roles as CSS variables ----------------
  # Inlined by the root layout from the theme dir, so the toggle reaches the browser on reload.
  # Kebab-cased role names; the font stack rides along. Roles only — the page names no hue.
  webCss =
    let
      kebab = k: lib.toLower (lib.replaceStrings [ "A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z" ] [ "-a" "-b" "-c" "-d" "-e" "-f" "-g" "-h" "-i" "-j" "-k" "-l" "-m" "-n" "-o" "-p" "-q" "-r" "-s" "-t" "-u" "-v" "-w" "-x" "-y" "-z" ] k);
      vars = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--${kebab k}:${hex v};") r);
    in "/* ${gen} */\n:root { ${vars} --font:${fontStack}; }\n";

  # ---- Claude Code: a custom theme per palette (~/.claude/themes/<name>.json) -------------
  # The keys are Claude Code's; Andrew's hand-made high-contrast theme was the model (green
  # body text there, on purpose). `light` tells whether the ground is light.
  claudeTheme = { name, light }:
    let
      t = c: hex (low c);
      # message grounds: a tint of the hue on the ground, one step off it
      tint = if light then r.card else r.panel;
      tint2 = if light then r.inputGround else r.card;
    in
    builtins.toJSON {
      inherit name;
      base = if light then "light" else "dark";
      overrides = {
        text = t r.userVoice; claude = t r.assistantVoice; inverseText = t r.ground; background = t r.ground;
        subtle = t r.meta; inactive = t r.inactive; suggestion = t r.attention; permission = t r.attention;
        remember = t r.assistant; success = t r.live; error = t r.alarm; warning = t r.warn;
        merged = t r.attention; promptBorder = t r.borderActive; planMode = t r.key; autoAccept = t r.cursorField;
        fastMode = t r.attention; bashBorder = t r.structure; ide = t r.key; thinking = t r.key;
        toolUse = t r.body; agentsView = t r.live; subagentStatusLine = t r.body;
        diffAdded = t (if light then "D6EDD6" else "0C2E0C"); diffAddedWord = t (if light then "A8DCA8" else "1B5E1B");
        diffAddedDimmed = t (if light then "E6F2E6" else "081F08");
        diffRemoved = t (if light then "F2D9D9" else "2E0C0C"); diffRemovedWord = t (if light then "E3AFAF" else "5E1B1B");
        diffRemovedDimmed = t (if light then "F7E8E8" else "1F0808");
        userMessageBackground = t tint; userMessageBackgroundHover = t tint2;
        bashMessageBackgroundColor = t r.hoverGround; memoryBackgroundColor = t tint;
        selectionBg = t r.selSoft; composerSidebarBackground = t tint;
        rate_limit_fill = t r.live; rate_limit_empty = t tint2;
        briefLabelYou = t r.cursorField; briefLabelClaude = t r.live;
        claudeShimmer = t r.cursorField; warningShimmer = t r.cursorField; permissionShimmer = t r.attention;
        promptBorderShimmer = t r.cursorField; inactiveShimmer = t r.inactive; fastModeShimmer = t r.attention;
        red_FOR_SUBAGENTS_ONLY = t r.alarm; blue_FOR_SUBAGENTS_ONLY = t r.key;
        green_FOR_SUBAGENTS_ONLY = t r.live; yellow_FOR_SUBAGENTS_ONLY = t r.cursorField;
        purple_FOR_SUBAGENTS_ONLY = t r.assistant; orange_FOR_SUBAGENTS_ONLY = t r.borderActive2;
        pink_FOR_SUBAGENTS_ONLY = t r.attention; cyan_FOR_SUBAGENTS_ONLY = t r.key;
      };
    };

  # claude-powerline (the statusline's renderer): the segment colours, on the ground
  # segments render in key order and builtins.toJSON sorts keys, so the lines are literal JSON:
  # dir / git / model, then ctx / 5h / wk
  claudePowerlineJson =
    let
      colors = builtins.toJSON {
        directory = { bg = hex r.panel; fg = hex r.assistant; };
        git = { bg = hex r.panel; fg = hex r.attention; };
        model = { bg = hex r.panel; fg = hex r.attention; };
        context = { bg = hex r.panel; fg = hex r.live; };
        block = { bg = hex r.panel; fg = hex r.cursorField; };
        weekly = { bg = hex r.panel; fg = hex r.assistant; };
      };
    in
    ''{"theme":"custom","display":{"style":"minimal","charset":"unicode","autoWrap":false,"lines":[''
    + ''{"segments":{"directory":{"enabled":true,"style":"fish"},"git":{"enabled":true},"model":{"enabled":true}}},''
    + ''{"segments":{"context":{"enabled":true,"percentageMode":"used"},"block":{"enabled":true},"weekly":{"enabled":true}}}''
    + '']},"colors":{"custom":${colors}}}'';

  # ---- terminals -----------------------------------------------------------------------
  ghosttyTheme =
    let
      pal = lib.concatImapStringsSep "\n" (i: c: "palette = ${toString (i - 1)}=${hex c}") p.ansiList;
    in
    ''
      # ${gen}
      background = ${hex r.ground}
      foreground = ${hex r.body}
      cursor-color = ${hex r.body}
      cursor-text = ${hex r.fieldInk}
      selection-background = ${hex r.selField}
      selection-foreground = ${hex r.selInk}
      ${pal}
    '';
  ghosttyConfig = template: ''
    # ${gen} (theme + font); the rest is templates/ghostty.conf in the repo.
    theme = ficciones
    font-family = ${f.family}
    font-size = ${toString f.size}
    # The floor for colour we do NOT own. Our own pairs clear AAA by construction and
    # checks.palette-contrast proves it; this catches what a program picks for itself — a 256-colour
    # index, a vendored theme, bare `fg=white` on a light ground — and lifts it to WCAG AA rather
    # than letting it render unreadable. Higher than this starts flattening third-party colour
    # toward black and white, which costs more than it buys.
    minimum-contrast = 4.5
    # Take the window chrome (tab bar, headerbar) from OUR background/foreground rather than from
    # GTK. GTK loads ~/.config/gtk-4.0/gtk.css once at startup, so on a live theme switch the tab
    # bar kept the colours it booted with while the terminal body had already changed; ghostty
    # re-reads this config on SIGUSR2, which the switch already sends.
    window-theme = ghostty
    ${template}
  '';

  kittyTheme =
    let
      names = [ "color0" "color1" "color2" "color3" "color4" "color5" "color6" "color7" "color8" "color9" "color10" "color11" "color12" "color13" "color14" "color15" ];
      pal = lib.concatStringsSep "\n" (lib.zipListsWith (n: c: "${n} ${hex c}") names p.ansiList);
    in
    ''
      # ${gen}. kitty.conf: `include theme.conf`
      font_family ${f.family}
      font_size ${toString f.size}
      background ${hex r.ground}
      foreground ${hex r.body}
      cursor ${hex r.body}
      cursor_text_color ${hex r.fieldInk}
      selection_background ${hex r.selField}
      selection_foreground ${hex r.selInk}
      url_color ${hex r.key}
      active_border_color ${hex r.borderActive}
      inactive_border_color ${hex r.borderInactive}
      active_tab_background ${hex r.cursorField}
      active_tab_foreground ${hex r.fieldInk}
      inactive_tab_background ${hex r.ground}
      inactive_tab_foreground ${hex r.inactive}
      ${pal}
    '';

  weztermTheme =
    let
      lst = xs: lib.concatMapStringsSep ", " (c: "\"${hex c}\"") xs;
    in
    ''
      # ${gen}. ~/.config/wezterm/colors/ficciones.toml — wezterm.lua: config.color_scheme = "ficciones"
      [colors]
      foreground = "${hex r.body}"
      background = "${hex r.ground}"
      cursor_bg = "${hex r.body}"
      cursor_fg = "${hex r.fieldInk}"
      cursor_border = "${hex r.body}"
      selection_bg = "${hex r.selField}"
      selection_fg = "${hex r.selInk}"
      ansi = [${lst (lib.take 8 p.ansiList)}]
      brights = [${lst (lib.drop 8 p.ansiList)}]

      [metadata]
      name = "ficciones"
      origin_url = "modules/desktop/theme/palette.nix"
    '';

  # ---- GTK -----------------------------------------------------------------------------
  # libadwaita's named colours, so every GTK4 app and the GTK3 ports pick up the palette
  # without a full theme. The law: the thing under your CURSOR — a highlighted menu item, a
  # list row, the active tab — is the amber field; a SELECTION you made and left behind, which
  # is text and only text in a toolkit this shape, is the violet field.
  gtkCss = ''
    /* ${gen} */
    @define-color accent_color ${hex r.accentField};
    @define-color accent_bg_color ${hex r.accentField};
    @define-color accent_fg_color ${hex r.fieldInk};
    @define-color destructive_color ${hex r.alarm};
    @define-color destructive_bg_color ${hex r.alarmField};
    @define-color destructive_fg_color ${hex r.fieldInk};
    @define-color success_color ${hex r.live};
    @define-color success_bg_color ${hex r.liveField};
    @define-color success_fg_color ${hex r.fieldInk};
    @define-color warning_color ${hex r.warn};
    @define-color warning_bg_color ${hex r.warnField};
    @define-color warning_fg_color ${hex r.fieldInk};
    @define-color error_color ${hex r.alarm};
    @define-color error_bg_color ${hex r.alarmField};
    @define-color error_fg_color ${hex r.fieldInk};
    @define-color window_bg_color ${hex r.ground};
    @define-color window_fg_color ${hex r.body};
    @define-color view_bg_color ${hex r.ground};
    @define-color view_fg_color ${hex r.body};
    @define-color headerbar_bg_color ${hex r.panel};
    @define-color headerbar_fg_color ${hex r.body};
    @define-color headerbar_border_color ${hex r.structure};
    @define-color headerbar_backdrop_color ${hex r.ground};
    @define-color headerbar_shade_color rgba(0, 0, 0, 0.36);
    @define-color headerbar_darker_shade_color rgba(0, 0, 0, 0.72);
    @define-color sidebar_bg_color ${hex r.panel};
    @define-color sidebar_fg_color ${hex r.body};
    @define-color sidebar_backdrop_color ${hex r.ground};
    @define-color sidebar_border_color ${hex r.structure};
    @define-color sidebar_shade_color rgba(0, 0, 0, 0.36);
    @define-color secondary_sidebar_bg_color ${hex r.card};
    @define-color secondary_sidebar_fg_color ${hex r.body};
    @define-color secondary_sidebar_backdrop_color ${hex r.ground};
    @define-color secondary_sidebar_border_color ${hex r.structure};
    @define-color secondary_sidebar_shade_color rgba(0, 0, 0, 0.36);
    @define-color card_bg_color ${hex r.card};
    @define-color card_fg_color ${hex r.body};
    @define-color card_shade_color rgba(0, 0, 0, 0.36);
    @define-color dialog_bg_color ${hex r.card};
    @define-color dialog_fg_color ${hex r.body};
    @define-color popover_bg_color ${hex r.card};
    @define-color popover_fg_color ${hex r.body};
    @define-color popover_shade_color rgba(0, 0, 0, 0.36);
    @define-color thumbnail_bg_color ${hex r.card};
    @define-color thumbnail_fg_color ${hex r.body};
    @define-color shade_color rgba(0, 0, 0, 0.36);
    @define-color scrollbar_outline_color ${hex r.structure};
    @define-color borders ${hex r.structure};
    /* GTK3 legacy names */
    @define-color theme_bg_color ${hex r.ground};
    @define-color theme_fg_color ${hex r.body};
    @define-color theme_base_color ${hex r.ground};
    @define-color theme_text_color ${hex r.body};
    @define-color theme_selected_bg_color ${hex r.cursorField};
    @define-color theme_selected_fg_color ${hex r.fieldInk};
    @define-color theme_unfocused_bg_color ${hex r.ground};
    @define-color theme_unfocused_fg_color ${hex r.inactive};
    @define-color insensitive_bg_color ${hex r.card};
    @define-color insensitive_fg_color ${hex r.inactive};
    @define-color unfocused_borders ${hex r.borderInactive};
    @define-color link_color ${hex r.key};
    @define-color visited_link_color ${hex r.assistant};

    * { font-family: ${fontStack}; }
    selection { background-color: ${hex r.selField}; color: ${hex r.selInk}; }
    *:selected { background-color: ${hex r.cursorField}; color: ${hex r.fieldInk}; }
    link, label.link, *:link { color: ${hex r.key}; }
    tooltip { background-color: ${hex r.card}; color: ${hex r.body}; border: 1px solid ${hex r.structure}; }
  '';
  gtkSettingsIni = ''
    [Settings]
    gtk-font-name=${f.family} ${toString f.size}
    gtk-application-prefer-dark-theme=true
    gtk-icon-theme-name=Papirus-Dark
    gtk-cursor-theme-name=Bibata-Modern-Classic
    gtk-cursor-theme-size=24
  '';

  # ---- Qt: qt6ct colour scheme + kvantum + a stylesheet ---------------------------------
  # qt6ct's 21 QPalette roles in order: WindowText Button Light Midlight Dark Mid Text
  # BrightText ButtonText Base Window Shadow Highlight HighlightedText Link LinkVisited
  # AlternateBase ToolTipBase ToolTipText PlaceholderText Accent.
  qt6ctColors =
    let
      roles = alpha: with r; [
        "#${alpha}${body}" "#ff${card}" "#ff${edge}" "#ff${raised}" "#ff${ground}" "#ff${inputGround}"
        "#${alpha}${body}" "#ff${cursorField}" "#${alpha}${body}" "#ff${ground}" "#ff${panel}" "#ff${ground}"
        "#ff${cursorField}" "#ff${fieldInk}" "#ff${key}" "#ff${assistant}" "#ff${card}" "#ff${card}"
        "#ff${body}" "#ff${inactive}" "#ff${body}"
      ];
      row = alpha: lib.concatStringsSep ", " (map low (roles alpha));
    in
    ''
      [ColorScheme]
      active_colors=${row "ff"}
      inactive_colors=${row "cc"}
      disabled_colors=${row "50"}
    '';
  qt6ctConf = ''
    [Appearance]
    color_scheme_path=${config_home}/qt6ct/colors/ficciones.conf
    custom_palette=true
    icon_theme=breeze-dark
    standard_dialogs=default
    style=kvantum
    stylesheets=${config_home}/qt6ct/qss/ficciones.qss

    [Fonts]
    fixed="${f.family},${toString f.size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    general="${f.family},${toString f.size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"

    [Interface]
    activate_item_on_single_click=1
    buttonbox_layout=0
    cursor_flash_time=1000
    dialog_buttons_have_icons=1
    double_click_interval=400
    keyboard_scheme=2
    menus_have_icons=true
    show_shortcuts_in_context_menus=true
    toolbutton_style=4
    underline_shortcut=1
    wheel_scroll_lines=3

    [Troubleshooting]
    force_raster_widgets=1
  '';
  config_home = "/home/andrew/.config";
  kvantumConfig = fill (builtins.readFile ./templates/kvantum/ficciones.kvconfig) templateSubs;
  kvantumSvg = fill (builtins.readFile ./templates/kvantum/ficciones.svg) templateSubs;
  qss = "/* ${gen} */\n" + fill (builtins.readFile ./templates/ficciones.qss) templateSubs;

  # ---- btop ----------------------------------------------------------------------------
  btopTheme =
    let
      kv = lib.mapAttrsToList (k: v: "theme[${k}]=${hex v}");
    in
    "# ${gen}\n" + lib.concatStringsSep "\n" (kv (with r; {
      main_bg = ground; main_fg = body; title = key; hi_fg = key; selected_bg = cursorField; selected_fg = fieldInk;
      inactive_fg = inactive; graph_text = meta; meter_bg = raised; proc_misc = meta;
      cpu_box = structure; mem_box = structure; net_box = structure; proc_box = structure; div_line = borderInactive;
      # every gauge runs the same ramp: fine, then working, then alarming
      temp_start = live; temp_mid = body; temp_end = alarm;
      cpu_start = live; cpu_mid = body; cpu_end = alarm;
      free_start = live; free_mid = body; free_end = alarm;
      cached_start = key; cached_mid = assistant; cached_end = attention;
      available_start = live; available_mid = body; available_end = alarm;
      used_start = live; used_mid = body; used_end = alarm;
      download_start = key; download_mid = assistant; download_end = attention;
      upload_start = live; upload_mid = body; upload_end = alarm;
      process_start = live; process_mid = body; process_end = alarm;
    })) + "\n";

  # ---- floorp: the vendored RetroTerminal CSS with its :root block generated ----------
  # One :root, not a prefers-color-scheme pair: the flake decides which palette is live, so
  # floorp must not second-guess it with a hand-written light theme that drifts.
  floorpRoot =
    lib.concatStringsSep "\n" (map (s: "    " + s) (with r; [
      "--retro-bg: ${hex ground};"
      "--retro-bg-elevated: ${hex panel};"
      "--retro-surface: ${hex inputGround};"
      "--retro-surface-dim: ${hex card};"
      "--retro-accent: ${hex accentField};"
      "--retro-accent-dim: ${hex visited};"
      "--retro-text: ${hex body};"
      "--retro-text-secondary: ${hex meta};"
      "--retro-text-dim: ${hex inactive};"
      # borders are `structure` like everywhere else — the menu tint was 1.5:1 against the
      # ground, which is why floorp's menus and popups looked like they had no edge at all
      "--retro-border: ${hex structure};"
      "--retro-border-bright: ${hex borderActive};"
      "--retro-font: ${fontStack};"
      "--retro-green: ${hex live};"
      "--retro-chip: ${hex cursorField};"
      "--retro-ink: ${hex fieldInk};"
      "--retro-sel: ${hex selField};"
      "--retro-sel-ink: ${hex selInk};"
      "--retro-cyan: ${hex key};"
      "--retro-pink: ${hex attention};"
      "--retro-red: ${hex alarm};"
    ]));
  floorpFile = name:
    "/* ${gen} (the :root block); the body is templates/floorp/${name} in the repo. */\n"
    + lib.replaceStrings [ "@ROOT@" "@FONT_STACK@" ] [ floorpRoot fontStack ]
      (fill (builtins.readFile (./templates/floorp + "/${name}")) templateSubs);
  floorpUserChrome = floorpFile "userChrome.css";
  # the sites too, not just the chrome: floorp-sites.nix appends @-moz-document blocks
  floorpUserContent = floorpFile "userContent.css" + "\n/* ---- sites (floorp-sites.nix) ---- */\n"
    + import ./floorp-sites.nix { inherit hex r fontStack; };

  # ---- hyprland / hyprlock -------------------------------------------------------------
  # dofile'd as ~/.config/hypr/theme.lua: only the colours live here. Env lines are appended by
  # the home-manager module, which knows the GTK/Qt theme options.
  hyprlandThemeLua = ''
    -- ${gen}
    local theme = {
        general = {
            col = {
                active_border = { colors = { "rgba(${r.body}ff)", "rgba(${r.borderActive2}ff)" }, angle = 45 },
                inactive_border = { colors = { "rgba(${r.borderInactive}ff)", "rgba(${r.borderInactive2}ff)" }, angle = 45 },
            },
        },
        group = {
            col = {
                border_active = "rgba(${r.body}ff)",
                border_inactive = "rgba(${r.borderInactive}ff)",
                border_locked_active = "rgba(${r.attention}ff)",
                border_locked_inactive = "rgba(${r.attentionDim}ff)",
            },
            groupbar = {
                font_family = "${f.family}",
                text_color = "rgba(${r.fieldInk}ff)",
                col = { active = "rgba(${r.cursorField}ff)", inactive = "rgba(${r.raised}ff)" },
            },
        },
        misc = {
            background_color = "rgba(${r.ground}ff)",
            font_family = "${f.family}",
        },
    }

    -- hyprexpo registers these keys only when the plugin is LOADED, and "installed" is not the
    -- same thing. hyprpm keeps its built .so under /var/cache/hyprpm/$USER/ with an ABI hash that
    -- must match the running Hyprland; a stale one is refused and nothing loads while the file
    -- sits there (2026-09-12: the plugin was built against aq_0.14, Hyprland wanted aq_0.15).
    -- So ask the compositor, not the filesystem. At the first parse the IPC socket may not be up,
    -- which answers "no" — correct, since nothing is loaded yet — and hyprland.lua loads the
    -- plugin at start, which re-reads this file with the keys valid.
    local function hyprexpo_loaded()
        local pipe = io.popen("hyprctl plugin list 2>/dev/null")
        if not pipe then return false end
        local out = pipe:read("*a") or ""
        pipe:close()
        return out:find("hyprexpo", 1, true) ~= nil
    end
    if hyprexpo_loaded() then
        theme.plugin = {
            hyprexpo = {
                    bg_col = "rgba(${r.ground}ff)",
                    gaps_in = 12,
                    gaps_out = 24,
                    tile_rounding = 8,
                    border_width = 2,
                    border_color = "rgba(${r.structure}ff)",
                    border_color_current = "rgba(${r.live}ff)",
                    border_color_focus = "rgba(${r.cursorField}ff)",
                    border_color_hover = "rgba(${r.attention}ff)",
                    label_font_family = "${f.family}",
                    label_font_size = 18,
                    label_position = "top-left",
                    label_bg_shape = "square",
                    label_bg_color = "rgba(${r.ground}ff)",
                    label_color_default = "rgba(${r.meta}ff)",
                    label_color_current = "rgba(${r.live}ff)",
                    label_color_focus = "rgba(${r.cursorField}ff)",
                    label_color_hover = "rgba(${r.attention}ff)",
                    selection_label_color = "rgba(${r.key}ff)",
                    keynav_enable = 1,
            },
        }
    end

    hl.config(theme)
  '';
  # The dashboard's chrome on the lock screen (style/_drawer.scss + _tui.scss): a ground board
  # with a 3px attention frame and 12px corners, carrying SQUARE cards — .panel is
  # border-radius 0 — that each wear a 1px hued border with a partner-hued 1px outline 10px
  # outside it ("card on a panel"), and a title tag notched into the top rule (.panel-title is
  # pulled up onto the border on a ground background). Hues follow the board's own pairs:
  # .card-now is body/assistant, .card-today is attention/key.
  #
  # hyprlock has no layout engine and no z-index we rely on, so this is literal geometry:
  # every position is an offset from screen centre, widgets paint in declaration order (board,
  # outlines, cards, tag patches, then text), and a card's outline is simply its box + 20 in
  # both axes. Sizes are even so the halves stay integral.
  hyprlockConf = ''
    # ${gen}
    general {
        hide_cursor = true
        ignore_empty_input = true
    }
    background {
        monitor =
        color = rgba(${r.ground}ff)
    }

    # ---- the board: ground sheet, heavy accent frame, 12px corners ----------------------
    shape {
        monitor =
        size = 820, 460
        color = rgba(${r.ground}ff)
        rounding = 12
        border_size = 3
        border_color = rgba(${r.attention}ff)
        position = 0, 0
        halign = center
        valign = center
    }

    # ---- card "now" (body / assistant) — outline first, then the card ------------------
    shape {
        monitor =
        size = 720, 230
        color = rgba(00000000)
        rounding = 0
        border_size = 1
        border_color = rgba(${r.assistant}ff)
        position = 0, 75
        halign = center
        valign = center
    }
    shape {
        monitor =
        size = 700, 210
        color = rgba(${r.ground}ff)
        rounding = 0
        border_size = 1
        border_color = rgba(${r.body}ff)
        position = 0, 75
        halign = center
        valign = center
    }

    # ---- card "unlock" (attention / key) ------------------------------------------------
    shape {
        monitor =
        size = 720, 140
        color = rgba(00000000)
        rounding = 0
        border_size = 1
        border_color = rgba(${r.key}ff)
        position = 0, -128
        halign = center
        valign = center
    }
    shape {
        monitor =
        size = 700, 120
        color = rgba(${r.ground}ff)
        rounding = 0
        border_size = 1
        border_color = rgba(${r.attention}ff)
        position = 0, -128
        halign = center
        valign = center
    }

    # ---- the title tags: a ground patch ON the top rule, then the word over it ----------
    # x = card left (-350) + the tag's 8px inset + half its own width, as .panel-title's
    # margin-left does; the patch is what makes the rule appear to break for the word.
    shape {
        monitor =
        size = 46, 18
        color = rgba(${r.ground}ff)
        rounding = 0
        border_size = 0
        position = -319, 180
        halign = center
        valign = center
    }
    shape {
        monitor =
        size = 68, 18
        color = rgba(${r.ground}ff)
        rounding = 0
        border_size = 0
        position = -308, -68
        halign = center
        valign = center
    }
    label {
        monitor =
        text = now
        color = rgba(${r.body}ff)
        font_size = ${toString f.size}
        font_family = ${f.family}
        position = -319, 180
        halign = center
        valign = center
    }
    label {
        monitor =
        text = unlock
        color = rgba(${r.attention}ff)
        font_size = ${toString f.size}
        font_family = ${f.family}
        position = -308, -68
        halign = center
        valign = center
    }

    # ---- card contents: the board's .bigtime is 52px, its body type 12 ------------------
    label {
        monitor =
        text = cmd[update:1000] echo "$(date +'%H:%M')"
        color = rgba(${r.body}ff)
        font_size = 52
        font_family = ${f.family}
        position = 0, 105
        halign = center
        valign = center
    }
    label {
        monitor =
        text = cmd[update:60000] echo "$(date +'%A %-d %B')"
        color = rgba(${r.key}ff)
        font_size = ${toString f.size}
        font_family = ${f.family}
        position = 0, 50
        halign = center
        valign = center
    }
    label {
        monitor =
        # NOT "$USER @ $HOST": hyprlock substitutes $USER but has no $HOST, so the old config
        # rendered the word "$HOST" on the lock screen. Caught by previewing in a nested
        # Hyprland, 2026-09-12. The shell has both.
        text = cmd[update:0] echo "$USER @ $(hostname)"
        color = rgba(${r.meta}ff)
        # the board drops identity type to 10px because it shows everything at once; nothing
        # competes for room here, and palette.nix biases type up, never down
        font_size = ${toString f.size}
        font_family = ${f.family}
        position = 0, 18
        halign = center
        valign = center
    }

    input-field {
        monitor =
        size = 560, 52
        outline_thickness = 1
        dots_size = 0.3
        dots_spacing = 0.3
        rounding = 0
        outer_color = rgba(${r.attention}ff)
        inner_color = rgba(${r.ground}ff)
        font_color = rgba(${r.body}ff)
        font_family = ${f.family}
        check_color = rgba(${r.live}ff)
        fail_color = rgba(${r.alarm}ff)
        fail_text = <i>$FAIL</i>
        placeholder_text = <span foreground="##${r.inactive}">password</span>
        capslock_color = rgba(${r.attention}ff)
        position = 0, -128
        halign = center
        valign = center
        fade_on_empty = false
    }
  '';

  # ---- lazygit / bat / fzf / cava / tmux --------------------------------------------------
  # starship: the prompt's chips are inverse video like the shell's (field = highlight, text = ink).
  # Read at every prompt, so the theme switch reaches the next line with no restart.
  starshipConfig = template:
    fill (lib.replaceStrings [ "@GEN@" ] [ gen ] template) { inherit (r) fieldInk key live body assistant alarm; };

  lazygitConfig = template:
    let
      # Built line by line: an indented '' string would strip the YAML indentation.
      entry = k: vs: [ "    ${k}:" ] ++ map (v: "      - ${v}") vs;
      q = c: "\"${hex c}\"";
      theme = lib.concatStringsSep "\n" (lib.concatLists [
        (entry "activeBorderColor" [ (q r.body) "bold" ])
        (entry "inactiveBorderColor" [ (q r.borderInactive) ])
        (entry "searchingActiveBorderColor" [ (q r.key) "bold" ])
        (entry "optionsTextColor" [ (q r.key) ])
        (entry "selectedLineBgColor" [ (q r.cursorField) ])
        (entry "inactiveViewSelectedLineBgColor" [ (q r.raised) ])
        (entry "cherryPickedCommitBgColor" [ (q r.selField) ])
        (entry "cherryPickedCommitFgColor" [ (q r.selInk) ])
        (entry "markedBaseCommitBgColor" [ (q r.selField) ])
        (entry "markedBaseCommitFgColor" [ (q r.selInk) ])
        (entry "unstagedChangesColor" [ (q r.alarm) ])
        (entry "defaultFgColor" [ (q r.body) ])
      ]);
    in
    "# ${gen} (gui.theme); the rest is templates/lazygit.yml in the repo.\n"
    + lib.replaceStrings [ "  theme: @THEME@\n" ] [ "  theme:\n${theme}\n" ] template;

  # bat: `ansi` is the honest choice — it renders through the terminal's 16 colours, which
  # ghostty already gets from this palette, so bat and the prompt agree by construction.
  batConfig = ''
    # ${gen}
    --theme=ansi
    --style=numbers,changes,header
    --paging=never
  '';

  # fzf: sourced by ~/.zshrc (FZF_THEME_FILE), which pre-dates this file and already looks for it.
  fzfTheme = ''
    # ${gen}
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
      --color=fg:${hex r.body},bg:${hex r.ground},hl:${hex r.key} \
      --color=fg+:${hex r.fieldInk},bg+:${hex r.cursorField},hl+:${hex r.fieldInk} \
      --color=info:${hex r.meta},prompt:${hex r.key},pointer:${hex r.body} \
      --color=marker:${hex r.selField},spinner:${hex r.attention},header:${hex r.meta} \
      --color=border:${hex r.structure},label:${hex r.key},query:${hex r.body}"
  '';

  cavaConfig = template:
    "# ${gen} ([color]); the rest is templates/cava.conf in the repo.\n" + template + ''

      [color]
      gradient = 1
      gradient_count = 6
      gradient_color_1 = '${hex r.live}'
      gradient_color_2 = '${hex r.cursorField}'
      gradient_color_3 = '${hex r.body}'
      gradient_color_4 = '${hex r.borderActive2}'
      gradient_color_5 = '${hex r.attention}'
      gradient_color_6 = '${hex r.alarm}'
    '';

  # The status-line lines flake.nix's programs.tmux.extraConfig splices in.
  tmuxStyle = ''
    set -g status-style "bg=default,fg=${hex r.body}"
    set -g window-status-current-style "fg=${hex r.fieldInk},bg=${hex r.body},bold"
    set -g window-status-style "fg=${hex r.inactive}"
    set -g window-status-activity-style "fg=${hex r.live}"
    set -g window-status-bell-style "fg=${hex r.alarm},bold"
    set -g message-style "fg=${hex r.key},bg=default"
    set -g mode-style "fg=${hex r.selInk},bg=${hex r.selField}"
    set -g pane-border-style "fg=${hex r.borderInactive}"
    set -g pane-active-border-style "fg=${hex r.body}"
  '';

  # Convenience: the palette as shell exports, for scripts that draw.
  envSh = let h = p.hue; in "# ${gen}\n" + lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "PALETTE_${lib.toUpper k}=${hex v}") h) + "\nPALETTE_FONT=\"${f.family}\"\n";
}
