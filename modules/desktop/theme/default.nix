# home-manager: every themed surface written from palette.nix (render.nix). The shell and the
# console get theirs IN the repo (generated.nix, `mise theme:gen`); everything here lands in
# ~/.config and is a store file — none of it is edited by hand, so nothing needs to be live.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ficciones.desktop.theme;
  palette = import ./palette.nix;
  render = import ./render.nix { inherit lib palette; };
  tpl = name: builtins.readFile (./templates + "/${name}");

  # BOTH palettes rendered at install (2026-09-06): every surface has an uqbar (dark) and a zahir (light) copy
  # under ~/.config/ficciones/themes/<name>/, each app's fixed path is a symlink through
  # ~/.config/ficciones/theme (the one mutable link, made on activation if missing), and the
  # toggle repoints it — no nix, under a second. `palette.nix`/`current` remain the build-time
  # default (the checked-in generated files, Console.Palette).
  palettes = { uqbar = import ./palettes/uqbar.nix; zahir = import ./palettes/zahir.nix; };
  renders = lib.mapAttrs (_: p: import ./render.nix { inherit lib; palette = p; }) palettes;
  envLua =
    "hl.env(\"GTK_THEME\", \"${cfg.gtkTheme}\")\n"
    + "hl.env(\"QT_QPA_PLATFORMTHEME\", \"${cfg.qtPlatformTheme}\")\n"
    + lib.optionalString (cfg.qtPlatformTheme == "qt6ct") "hl.env(\"QT_STYLE_OVERRIDE\", \"kvantum\")\n";
  themeFiles = r: {
    "ghostty-theme" = r.ghosttyTheme;
    "kitty-theme.conf" = r.kittyTheme;
    "wezterm.toml" = r.weztermTheme;
    "gtk.css" = r.gtkCss;
    "qt6ct-colors.conf" = r.qt6ctColors;
    "qt.qss" = r.qss;
    "kvantum.kvconfig" = r.kvantumConfig;
    "kvantum.svg" = r.kvantumSvg;
    "btop.theme" = r.btopTheme;
    "hypr-theme.lua" = r.hyprlandThemeLua + envLua;
    "hyprlock.conf" = r.hyprlockConf;
    "lazygit.yml" = r.lazygitConfig (tpl "lazygit.yml");
    "starship.toml" = r.starshipConfig (tpl "starship.toml");
    "bat-config" = r.batConfig;
    "fzf.zsh" = r.fzfTheme;
    "cava.conf" = r.cavaConfig (tpl "cava.conf");
    "tmux.conf" = r.tmuxStyle;
    "palette.sh" = r.envSh;
    "shell-palette.json" = r.paletteJson;
    "claude-powerline.json" = r.claudePowerlineJson;
    "floorp-userChrome.css" = r.floorpUserChrome;
    "floorp-userContent.css" = r.floorpUserContent;
  };
  themeDir = "${config.xdg.configHome}/ficciones/theme";
  # an app's fixed path → the theme dir's copy, through the one mutable link
  via = file: { source = config.lib.file.mkOutOfStoreSymlink "${themeDir}/${file}"; };
in
{
  options.ficciones.desktop.theme = {
    palette = lib.mkOption {
      type = lib.types.attrs;
      default = palette;
      readOnly = true;
      description = "The palette (modules/desktop/theme/palette.nix), for other modules that need a value.";
    };
    render = lib.mkOption {
      type = lib.types.attrs;
      default = render;
      readOnly = true;
      description = "The rendered surfaces (render.nix): flake.nix splices tmuxStyle from here.";
    };
    floorpProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "d0p2n4mq.default-nightly-1725500522201" ];
      description = "Profile directories under ~/.floorp that get userChrome.css/userContent.css.";
    };
    qtPlatformTheme = lib.mkOption {
      type = lib.types.enum [ "qt6ct" "gtk3" ];
      default = "gtk3";
      description = ''
        How Qt apps get the palette. "qt6ct" (+ kvantum) is the real thing and what modules/os
        installs; "gtk3" is Qt's own platform theme, which derives a palette from the GTK theme
        and our gtk.css — the honest choice on the Arch box, where qt6ct was never installed.
      '';
    };
    gtkTheme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha-yellow-standard+default";
      description = ''
        The GTK theme under the @define-color overrides — the overrides carry the palette, the
        theme carries widget shapes. Installed by the OS (pacman today, fonts/themes in modules/os later).
      '';
    };
  };

  config = {
    # the one font, plus coverage for what it has no glyphs for: non-Latin text and emoji
    home.packages = [ pkgs.nerd-fonts.comic-shanns-mono pkgs.noto-fonts pkgs.noto-fonts-cjk-sans pkgs.noto-fonts-color-emoji ];
    # fontconfig reads ~/.nix-profile/share/fonts only through this (it writes the conf.d entry).
    # Every generic family resolves to THE font — mono for sans and serif too (Andrew, 2026-09-07:
    # easier on his eyes than any proportional face); Noto only fills the glyphs it lacks.
    fonts.fontconfig = {
      enable = true;
      defaultFonts = rec {
        monospace = [ palette.font.family palette.font.mono "Noto Sans Mono" "Noto Sans CJK SC" "Noto Color Emoji" ];
        sansSerif = [ palette.font.family "Noto Sans" "Noto Sans CJK SC" "Noto Color Emoji" ];
        serif = sansSerif;
        emoji = [ "Noto Color Emoji" ];
      };
    };

    # GTK reads org.gnome.desktop.interface AHEAD of settings.ini on Wayland, and a D-Bus-activated
    # app (gcr-prompter, the portal dialogs) never sees Hyprland's GTK_THEME — a stale
    # `adw-gtk3-dark` here (caelestia's) left every one of those on stock Adwaita light (2026-09-07).
    # color-scheme is NOT declared: the shell's theme switch owns it live.
    dconf.settings."org/gnome/desktop/interface" = {
      gtk-theme = cfg.gtkTheme;
      font-name = "${palette.font.family} ${toString palette.font.size}";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Bibata-Modern-Classic";
      cursor-size = 24;
    };

    xdg.configFile = lib.mkMerge [
      # every surface, both palettes
      (lib.mkMerge (lib.mapAttrsToList (name: r:
        lib.mapAttrs' (file: text: lib.nameValuePair "ficciones/themes/${name}/${file}" { inherit text; }) (themeFiles r)
        // {
          # the shell's stylesheet for this palette, compiled in the shell package
          "ficciones/themes/${name}/shell.css".source = "${config.ficciones.desktop.shell.package}/share/astal-shell/themes/${name}.css";
        }) renders))
      {
        # ghostty: the theme file + the config that names it (templates/ghostty.conf is the rest).
        "ghostty/themes/ficciones" = via "ghostty-theme";
        "ghostty/config".text = render.ghosttyConfig (tpl "ghostty.conf");

        # kitty / wezterm — theme files only; each config includes its own (comment in the file).
        "kitty/theme.conf" = via "kitty-theme.conf";
        "wezterm/colors/ficciones.toml" = via "wezterm.toml";

        # GTK 3/4: libadwaita's named colours + the font, over whichever theme draws the widgets.
        "gtk-3.0/gtk.css" = via "gtk.css";
        "gtk-4.0/gtk.css" = via "gtk.css";

        # starship reads it at every prompt: the switch lands on the next line
        "starship.toml" = via "starship.toml";
        "gtk-3.0/settings.ini".text = render.gtkSettingsIni + "gtk-theme-name=${cfg.gtkTheme}\n";
        # libadwaita refuses gtk-application-prefer-dark-theme (a warning at every shell start); GTK 4
        # takes the scheme from the portal's color-scheme, which the theme switch sets
        "gtk-4.0/settings.ini".text = builtins.replaceStrings [ "gtk-application-prefer-dark-theme=true\n" ] [ "" ] render.gtkSettingsIni + "gtk-theme-name=${cfg.gtkTheme}\n";

        # Qt: qt6ct owns the palette + font, kvantum draws the widgets, the qss covers what neither reaches.
        "qt6ct/qt6ct.conf".text = render.qt6ctConf;
        "qt6ct/colors/ficciones.conf" = via "qt6ct-colors.conf";
        "qt6ct/qss/ficciones.qss" = via "qt.qss";
        "qt5ct/qt5ct.conf".text = builtins.replaceStrings [ "qt6ct" ] [ "qt5ct" ] render.qt6ctConf;
        "qt5ct/colors/ficciones.conf" = via "qt6ct-colors.conf";
        "qt5ct/qss/ficciones.qss" = via "qt.qss";
        "Kvantum/kvantum.kvconfig".text = "[General]\ntheme=ficciones\n";
        "Kvantum/ficciones/ficciones.kvconfig" = via "kvantum.kvconfig";
        "Kvantum/ficciones/ficciones.svg" = via "kvantum.svg";

        "btop/themes/ficciones.theme" = via "btop.theme";

        # Hyprland colours (dofile'd by hyprland.lua) and the lock screen.
        "hypr/theme.lua" = via "hypr-theme.lua";
        "hypr/hyprlock.conf" = via "hyprlock.conf";

        "lazygit/config.yml" = via "lazygit.yml";
        "bat/config" = via "bat-config";
        "fzf/theme.zsh" = via "fzf.zsh";
        "cava/config" = via "cava.conf";

        # The palette as shell variables, for scripts that draw.
        "ficciones/palette.sh" = via "palette.sh";
      }
    ];

    # Claude Code's theme per palette; the switch points ~/.claude/settings.json at one
    home.file = {
      # the statusline (scripts/statusline-box.sh) and its renderer's config, per theme
      ".claude/statusline-box.sh" = { source = ../scripts/statusline-box.sh; executable = true; };
      ".claude/claude-powerline.json" = via "claude-powerline.json";
      ".claude/themes/uqbar.json".text = renders.uqbar.claudeTheme { name = "uqbar"; light = false; };
      ".claude/themes/zahir.json".text = renders.zahir.claudeTheme { name = "zahir"; light = true; };
    } // lib.listToAttrs (lib.concatMap (profile: [
      (lib.nameValuePair ".floorp/${profile}/chrome/userChrome.css" (via "floorp-userChrome.css"))
      (lib.nameValuePair ".floorp/${profile}/chrome/userContent.css" (via "floorp-userContent.css"))
    ]) cfg.floorpProfiles);

    # the one mutable link: made once, then owned by the toggle (astal-shell theme / Super+Shift+P)
    home.activation.ficcionesTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # a fresh home (the VM, a new install) has no ~/.config/ficciones yet; the themes/ tree
      # under it is linked by linkGeneration, which runs later in the same activation
      run mkdir -p "$(dirname "${themeDir}")"
      if [ ! -e "${themeDir}" ]; then run ln -sfn themes/uqbar "${themeDir}"; fi
    '';

    # btop rewrites btop.conf on exit, so it stays a real file; only the theme line is ours.
    home.activation.btopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="$HOME/.config/btop/btop.conf"
      if [ -f "$conf" ] && ! grep -q '^color_theme = "ficciones"' "$conf"; then
        run ${pkgs.gnused}/bin/sed -i 's/^color_theme = .*/color_theme = "ficciones"/' "$conf"
      fi
    '';
  };
}
