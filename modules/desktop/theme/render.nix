# Every themed surface as a pure string function of palette.nix. No pkgs, no config: the
# home-manager module (default.nix) writes these to ~/.config, the shell package bakes the
# first two into its bundle, and flake `checks.palette-sync` diffs the checked-in copies
# against them. Add a surface = add a function here; never hand-mirror a hex value.
{ lib, palette ? import ./palette.nix }:

let
  p = palette;
  h = p.hue;
  r = p.role;
  f = p.font;
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
  # The substitution map the vendored templates (kvantum, qss, floorp) use.
  templateSubs = {
    inherit (h) amber green bg amberDim amberSoft surface0 surface1 surface2 surface3 surface4 amberTint0 amberTint1 amberTint2;
  };
in
rec {
  # ---- the shell -----------------------------------------------------------------------
  paletteScss = ''
    // ${gen}. _tokens.scss forwards this and adds the metrics. Rule: body text amber on black; green/pink highlights; active = inverse video.
    $bg:     ${hex h.bg};
    $ink:    ${hex h.ink};   // chip text — dark on a bright field
    $green:  ${hex h.green};   // highlight: live / ok / occupied
    $amber:  ${hex h.amber};   // body text AND chrome
    $chip:   ${hex h.chip};   // the inverse-video field
    $sel:    ${hex h.sel};   // selection / tab field
    $accent: ${hex h.pink};   // highlight: agents, the operator, attention
    $dim:    ${hex h.dim};
    $sep:    ${hex h.sep};   // structure: borders, rules
    $red:    ${hex h.red};
    $cyan:   ${hex h.cyan};
    $white:  ${hex h.white};
    $lilac:  ${hex h.lilac};
    $violet: ${hex h.violet};

    // status tier
    $st-working: ${hex p.status.working};
    $st-blocked: ${hex p.status.blocked};
    $st-await:   ${hex p.status.await};
    $st-open:    ${hex p.status.open};
    $st-done:    ${hex p.status.done};
    $st-idle:    ${hex p.status.idle};

    // text roles beyond the body: keys/labels cyan, secondary text lilac
    $key:  ${hex r.key};
    $meta: ${hex r.meta};

    // identity tier
    $arch-surveyor:  ${hex p.identity.surveyor};
    $arch-builder:   ${hex p.identity.builder};
    $arch-reviewer:  ${hex p.identity.reviewer};
    $arch-planner:   ${hex p.identity.planner};
    $arch-assistant: ${hex p.identity.assistant};

    // The one font. Low vision: sizes bias up, never down.
    $font: ${fontStack};

    // Hover/pressed fields: the body colour at low alpha, so hover reads as "lit", not recoloured.
    $hover: rgba($amber, 0.12);
    $pressed: rgba($amber, 0.22);
  '';

  paletteTs = ''
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
  '';

  # ---- Console.Style (modules/console) --------------------------------------------------
  consolePaletteEx =
    let
      line = name: c: "  def ${name}, do: 0x${c}";
      hues = lib.concatStringsSep "\n" (lib.mapAttrsToList line h);
    in
    ''
      # ${gen}
      defmodule Console.Palette do
        @moduledoc """
        The machine palette as 24-bit integers, one function per hue. `Console.Style` maps
        semantic styles onto these; nothing else in the cockpit names a colour.
        """
      ${hues}
      end
    '';

  # ---- terminals -----------------------------------------------------------------------
  ghosttyTheme =
    let
      pal = lib.concatImapStringsSep "\n" (i: c: "palette = ${toString (i - 1)}=${hex c}") p.ansiList;
    in
    ''
      # ${gen}
      background = ${hex h.bg}
      foreground = ${hex h.amber}
      cursor-color = ${hex h.amber}
      cursor-text = ${hex h.ink}
      selection-background = ${hex h.chip}
      selection-foreground = ${hex h.ink}
      ${pal}
    '';
  ghosttyConfig = template: ''
    # ${gen} (theme + font); the rest is templates/ghostty.conf in the repo.
    theme = ficciones
    font-family = ${f.family}
    font-size = ${toString f.size}
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
      background ${hex h.bg}
      foreground ${hex h.amber}
      cursor ${hex h.amber}
      cursor_text_color ${hex h.ink}
      selection_background ${hex h.chip}
      selection_foreground ${hex h.ink}
      url_color ${hex h.cyan}
      active_border_color ${hex h.amber}
      inactive_border_color ${hex h.amberDim}
      active_tab_background ${hex h.amber}
      active_tab_foreground ${hex h.ink}
      inactive_tab_background ${hex h.bg}
      inactive_tab_foreground ${hex h.dim}
      ${pal}
    '';

  weztermTheme =
    let
      lst = xs: lib.concatMapStringsSep ", " (c: "\"${hex c}\"") xs;
    in
    ''
      # ${gen}. ~/.config/wezterm/colors/ficciones.toml — wezterm.lua: config.color_scheme = "ficciones"
      [colors]
      foreground = "${hex h.amber}"
      background = "${hex h.bg}"
      cursor_bg = "${hex h.amber}"
      cursor_fg = "${hex h.ink}"
      cursor_border = "${hex h.amber}"
      selection_bg = "${hex h.chip}"
      selection_fg = "${hex h.ink}"
      ansi = [${lst (lib.take 8 p.ansiList)}]
      brights = [${lst (lib.drop 8 p.ansiList)}]

      [metadata]
      name = "ficciones"
      origin_url = "modules/desktop/theme/palette.nix"
    '';

  # ---- GTK -----------------------------------------------------------------------------
  # libadwaita's named colours, so every GTK4 app and the GTK3 ports pick up the palette
  # without a full theme. Selection = the chip (inverse video), accent = amber.
  gtkCss = ''
    /* ${gen} */
    @define-color accent_color ${hex h.amber};
    @define-color accent_bg_color ${hex h.amber};
    @define-color accent_fg_color ${hex h.ink};
    @define-color destructive_color ${hex h.red};
    @define-color destructive_bg_color ${hex h.red};
    @define-color destructive_fg_color ${hex h.ink};
    @define-color success_color ${hex h.green};
    @define-color success_bg_color ${hex h.green};
    @define-color success_fg_color ${hex h.ink};
    @define-color warning_color ${hex h.chip};
    @define-color warning_bg_color ${hex h.chip};
    @define-color warning_fg_color ${hex h.ink};
    @define-color error_color ${hex h.red};
    @define-color error_bg_color ${hex h.red};
    @define-color error_fg_color ${hex h.ink};
    @define-color window_bg_color ${hex h.bg};
    @define-color window_fg_color ${hex h.amber};
    @define-color view_bg_color ${hex h.bg};
    @define-color view_fg_color ${hex h.amber};
    @define-color headerbar_bg_color ${hex h.surface0};
    @define-color headerbar_fg_color ${hex h.amber};
    @define-color headerbar_border_color ${hex h.sep};
    @define-color headerbar_backdrop_color ${hex h.bg};
    @define-color headerbar_shade_color rgba(0, 0, 0, 0.36);
    @define-color headerbar_darker_shade_color rgba(0, 0, 0, 0.72);
    @define-color sidebar_bg_color ${hex h.surface0};
    @define-color sidebar_fg_color ${hex h.amber};
    @define-color sidebar_backdrop_color ${hex h.bg};
    @define-color sidebar_border_color ${hex h.sep};
    @define-color sidebar_shade_color rgba(0, 0, 0, 0.36);
    @define-color secondary_sidebar_bg_color ${hex h.surface1};
    @define-color secondary_sidebar_fg_color ${hex h.amber};
    @define-color secondary_sidebar_backdrop_color ${hex h.bg};
    @define-color secondary_sidebar_border_color ${hex h.sep};
    @define-color secondary_sidebar_shade_color rgba(0, 0, 0, 0.36);
    @define-color card_bg_color ${hex h.surface1};
    @define-color card_fg_color ${hex h.amber};
    @define-color card_shade_color rgba(0, 0, 0, 0.36);
    @define-color dialog_bg_color ${hex h.surface1};
    @define-color dialog_fg_color ${hex h.amber};
    @define-color popover_bg_color ${hex h.surface1};
    @define-color popover_fg_color ${hex h.amber};
    @define-color popover_shade_color rgba(0, 0, 0, 0.36);
    @define-color thumbnail_bg_color ${hex h.surface1};
    @define-color thumbnail_fg_color ${hex h.amber};
    @define-color shade_color rgba(0, 0, 0, 0.36);
    @define-color scrollbar_outline_color ${hex h.sep};
    @define-color borders ${hex h.sep};
    /* GTK3 legacy names */
    @define-color theme_bg_color ${hex h.bg};
    @define-color theme_fg_color ${hex h.amber};
    @define-color theme_base_color ${hex h.bg};
    @define-color theme_text_color ${hex h.amber};
    @define-color theme_selected_bg_color ${hex h.chip};
    @define-color theme_selected_fg_color ${hex h.ink};
    @define-color theme_unfocused_bg_color ${hex h.bg};
    @define-color theme_unfocused_fg_color ${hex h.dim};
    @define-color insensitive_bg_color ${hex h.surface1};
    @define-color insensitive_fg_color ${hex h.dim};
    @define-color unfocused_borders ${hex h.amberDim};
    @define-color link_color ${hex h.cyan};
    @define-color visited_link_color ${hex h.violet};

    * { font-family: ${fontStack}; }
    selection, *:selected { background-color: ${hex h.chip}; color: ${hex h.ink}; }
    link, label.link, *:link { color: ${hex h.cyan}; }
    tooltip { background-color: ${hex h.surface1}; color: ${hex h.amber}; border: 1px solid ${hex h.sep}; }
  '';
  gtkSettingsIni = ''
    [Settings]
    gtk-font-name=${f.family} ${toString f.size}
    gtk-application-prefer-dark-theme=true
    gtk-theme-name=Adwaita
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
      roles = alpha: with h; [
        "#${alpha}${amber}" "#ff${surface1}" "#ff${surface4}" "#ff${surface3}" "#ff${bg}" "#ff${surface2}"
        "#${alpha}${amber}" "#ff${chip}" "#${alpha}${amber}" "#ff${bg}" "#ff${surface0}" "#ff${bg}"
        "#ff${chip}" "#ff${ink}" "#ff${cyan}" "#ff${violet}" "#ff${surface1}" "#ff${surface1}"
        "#ff${amber}" "#ff${dim}" "#ff${amber}"
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
    "# ${gen}\n" + lib.concatStringsSep "\n" (kv (with h; {
      main_bg = bg; main_fg = amber; title = cyan; hi_fg = cyan; selected_bg = chip; selected_fg = ink;
      inactive_fg = dim; graph_text = lilac; meter_bg = surface3; proc_misc = lilac;
      cpu_box = sep; mem_box = sep; net_box = sep; proc_box = sep; div_line = amberDim;
      temp_start = green; temp_mid = amber; temp_end = red;
      cpu_start = green; cpu_mid = amber; cpu_end = red;
      free_start = green; free_mid = amber; free_end = red;
      cached_start = cyan; cached_mid = violet; cached_end = pink;
      available_start = green; available_mid = amber; available_end = red;
      used_start = green; used_mid = amber; used_end = red;
      download_start = cyan; download_mid = violet; download_end = pink;
      upload_start = green; upload_mid = amber; upload_end = red;
      process_start = green; process_mid = amber; process_end = red;
    })) + "\n";

  # ---- floorp: the vendored RetroTerminal CSS with the dark :root block generated ----------
  floorpRootDark =
    lib.concatStringsSep "\n" (map (s: "    " + s) (with h; [
      "--retro-bg: ${hex bg};"
      "--retro-bg-elevated: ${hex surface0};"
      "--retro-surface: ${hex surface2};"
      "--retro-surface-dim: ${hex surface1};"
      "--retro-accent: ${hex amber};"
      "--retro-accent-dim: ${hex amberSoft};"
      "--retro-text: ${hex amber};"
      "--retro-text-secondary: ${hex lilac};"
      "--retro-text-dim: ${hex dim};"
      "--retro-border: ${hex amberTint2};"
      "--retro-border-bright: ${hex amberDim};"
      "--retro-font: ${fontStack};"
      "--retro-green: ${hex green};"
      "--retro-cyan: ${hex cyan};"
      "--retro-pink: ${hex pink};"
      "--retro-red: ${hex red};"
    ]));
  floorpFile = name:
    "/* ${gen} (the :root block); the body is templates/floorp/${name} in the repo. */\n"
    + lib.replaceStrings [ "@ROOT_DARK@" "@FONT_STACK@" ] [ floorpRootDark fontStack ]
      (fill (builtins.readFile (./templates/floorp + "/${name}")) templateSubs);
  floorpUserChrome = floorpFile "userChrome.css";
  floorpUserContent = floorpFile "userContent.css";

  # ---- hyprland / hyprlock -------------------------------------------------------------
  # Sourced by hyprland.conf (and required by hyprland.lua): only the colours live here.
  hyprlandTheme = ''
    # ${gen}
    general {
        col.active_border = rgba(${h.amber}ff) rgba(${h.ember}ff) 45deg
        col.inactive_border = rgba(${h.amberDim}ff) rgba(${h.emberDim}ff) 45deg
    }
    group {
        col.border_active = rgba(${h.amber}ff)
        col.border_inactive = rgba(${h.amberDim}ff)
        col.border_locked_active = rgba(${h.pink}ff)
        col.border_locked_inactive = rgba(${h.sel}ff)
        groupbar {
            font_family = ${f.family}
            col.active = rgba(${h.chip}ff)
            col.inactive = rgba(${h.surface3}ff)
            text_color = rgba(${h.ink}ff)
        }
    }
    misc {
        background_color = rgba(${h.bg}ff)
        font_family = ${f.family}
    }
  '';
  hyprlockConf = ''
    # ${gen}
    general {
        hide_cursor = true
        ignore_empty_input = true
    }
    background {
        monitor =
        color = rgba(${h.bg}ff)
    }
    label {
        monitor =
        text = cmd[update:1000] echo "$(date +'%H:%M')"
        color = rgba(${h.amber}ff)
        font_size = 96
        font_family = ${f.family}
        position = 0, 160
        halign = center
        valign = center
    }
    label {
        monitor =
        text = $USER @ $HOST
        color = rgba(${h.lilac}ff)
        font_size = ${toString (f.sizeLg + 3)}
        font_family = ${f.family}
        position = 0, 60
        halign = center
        valign = center
    }
    input-field {
        monitor =
        size = 420, 56
        outline_thickness = 2
        dots_size = 0.3
        dots_spacing = 0.3
        outer_color = rgba(${h.amber}ff)
        inner_color = rgba(${h.bg}ff)
        font_color = rgba(${h.amber}ff)
        font_family = ${f.family}
        check_color = rgba(${h.cyan}ff)
        fail_color = rgba(${h.red}ff)
        fail_text = <i>$FAIL</i>
        placeholder_text = <span foreground="##${h.dim}">password</span>
        capslock_color = rgba(${h.pink}ff)
        position = 0, -40
        halign = center
        valign = center
        fade_on_empty = false
    }
  '';

  # ---- lazygit / bat / fzf / cava / tmux --------------------------------------------------
  lazygitConfig = template:
    let
      # Built line by line: an indented '' string would strip the YAML indentation.
      entry = k: vs: [ "    ${k}:" ] ++ map (v: "      - ${v}") vs;
      q = c: "\"${hex c}\"";
      theme = lib.concatStringsSep "\n" (lib.concatLists [
        (entry "activeBorderColor" [ (q h.amber) "bold" ])
        (entry "inactiveBorderColor" [ (q h.amberDim) ])
        (entry "searchingActiveBorderColor" [ (q h.cyan) "bold" ])
        (entry "optionsTextColor" [ (q h.cyan) ])
        (entry "selectedLineBgColor" [ (q h.chip) ])
        (entry "inactiveViewSelectedLineBgColor" [ (q h.surface3) ])
        (entry "cherryPickedCommitBgColor" [ (q h.sel) ])
        (entry "cherryPickedCommitFgColor" [ (q h.cream) ])
        (entry "markedBaseCommitBgColor" [ (q h.sel) ])
        (entry "markedBaseCommitFgColor" [ (q h.cream) ])
        (entry "unstagedChangesColor" [ (q h.red) ])
        (entry "defaultFgColor" [ (q h.amber) ])
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
      --color=fg:${hex h.amber},bg:${hex h.bg},hl:${hex h.cyan} \
      --color=fg+:${hex h.ink},bg+:${hex h.chip},hl+:${hex h.ink} \
      --color=info:${hex h.lilac},prompt:${hex h.cyan},pointer:${hex h.pink} \
      --color=marker:${hex h.green},spinner:${hex h.pink},header:${hex h.lilac} \
      --color=border:${hex h.sep},label:${hex h.cyan},query:${hex h.amber}"
  '';

  cavaConfig = template:
    "# ${gen} ([color]); the rest is templates/cava.conf in the repo.\n" + template + ''

      [color]
      gradient = 1
      gradient_count = 6
      gradient_color_1 = '${hex h.green}'
      gradient_color_2 = '${hex h.chip}'
      gradient_color_3 = '${hex h.amber}'
      gradient_color_4 = '${hex h.ember}'
      gradient_color_5 = '${hex h.pink}'
      gradient_color_6 = '${hex h.red}'
    '';

  # The status-line lines flake.nix's programs.tmux.extraConfig splices in.
  tmuxStyle = ''
    set -g status-style "bg=default,fg=${hex h.amber}"
    set -g window-status-current-style "fg=${hex h.ink},bg=${hex h.amber},bold"
    set -g window-status-style "fg=${hex h.dim}"
    set -g message-style "fg=${hex h.cyan},bg=default"
    set -g mode-style "fg=${hex h.ink},bg=${hex h.chip}"
    set -g pane-border-style "fg=${hex h.amberDim}"
    set -g pane-active-border-style "fg=${hex h.amber}"
  '';

  # Convenience: the palette as shell exports, for scripts (rotate-wallpaper, hyprpaper glue).
  envSh = "# ${gen}\n" + lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "PALETTE_${lib.toUpper k}=${hex v}") h) + "\nPALETTE_FONT=\"${f.family}\"\n";
}
