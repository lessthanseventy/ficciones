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
    home.packages = [ pkgs.nerd-fonts.comic-shanns-mono ];

    xdg.configFile = {
      # ghostty: the theme file + the config that names it (templates/ghostty.conf is the rest).
      "ghostty/themes/ficciones".text = render.ghosttyTheme;
      "ghostty/config".text = render.ghosttyConfig (tpl "ghostty.conf");

      # kitty / wezterm — theme files only; each config includes its own (comment in the file).
      "kitty/theme.conf".text = render.kittyTheme;
      "wezterm/colors/ficciones.toml".text = render.weztermTheme;

      # GTK 3/4: libadwaita's named colours + the font, over whichever theme draws the widgets.
      "gtk-3.0/gtk.css".text = render.gtkCss;
      "gtk-4.0/gtk.css".text = render.gtkCss;
      "gtk-3.0/settings.ini".text = render.gtkSettingsIni + "gtk-theme-name=${cfg.gtkTheme}\n";
      "gtk-4.0/settings.ini".text = render.gtkSettingsIni + "gtk-theme-name=${cfg.gtkTheme}\n";

      # Qt: qt6ct owns the palette + font, kvantum draws the widgets, the qss covers what neither reaches.
      "qt6ct/qt6ct.conf".text = render.qt6ctConf;
      "qt6ct/colors/ficciones.conf".text = render.qt6ctColors;
      "qt6ct/qss/ficciones.qss".text = render.qss;
      "qt5ct/qt5ct.conf".text = builtins.replaceStrings [ "qt6ct" ] [ "qt5ct" ] render.qt6ctConf;
      "qt5ct/colors/ficciones.conf".text = render.qt6ctColors;
      "qt5ct/qss/ficciones.qss".text = render.qss;
      "Kvantum/kvantum.kvconfig".text = "[General]\ntheme=ficciones\n";
      "Kvantum/ficciones/ficciones.kvconfig".text = render.kvantumConfig;
      "Kvantum/ficciones/ficciones.svg".text = render.kvantumSvg;

      "btop/themes/ficciones.theme".text = render.btopTheme;

      # Hyprland colours (dofile'd by hyprland.lua) and the lock screen.
      "hypr/theme.conf".text = # TRANSITION, see modules/desktop/default.nix
        render.hyprlandTheme
        + "env = GTK_THEME,${cfg.gtkTheme}\n"
        + "env = QT_QPA_PLATFORMTHEME,${cfg.qtPlatformTheme}\n"
        + lib.optionalString (cfg.qtPlatformTheme == "qt6ct") "env = QT_STYLE_OVERRIDE,kvantum\n";
      "hypr/theme.lua".text =
        render.hyprlandThemeLua
        + "hl.env(\"GTK_THEME\", \"${cfg.gtkTheme}\")\n"
        + "hl.env(\"QT_QPA_PLATFORMTHEME\", \"${cfg.qtPlatformTheme}\")\n"
        + lib.optionalString (cfg.qtPlatformTheme == "qt6ct") "hl.env(\"QT_STYLE_OVERRIDE\", \"kvantum\")\n";
      "hypr/hyprlock.conf".text = render.hyprlockConf;

      "lazygit/config.yml".text = render.lazygitConfig (tpl "lazygit.yml");
      "bat/config".text = render.batConfig;
      "fzf/theme.zsh".text = render.fzfTheme;
      "cava/config".text = render.cavaConfig (tpl "cava.conf");

      # The palette as shell variables, for scripts that draw (rotate-wallpaper, notify glue).
      "ficciones/palette.sh".text = render.envSh;
    };

    home.file = lib.listToAttrs (lib.concatMap (profile: [
      (lib.nameValuePair ".floorp/${profile}/chrome/userChrome.css" { text = render.floorpUserChrome; })
      (lib.nameValuePair ".floorp/${profile}/chrome/userContent.css" { text = render.floorpUserContent; })
    ]) cfg.floorpProfiles);

    # btop rewrites btop.conf on exit, so it stays a real file; only the theme line is ours.
    home.activation.btopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="$HOME/.config/btop/btop.conf"
      if [ -f "$conf" ] && ! grep -q '^color_theme = "ficciones"' "$conf"; then
        run ${pkgs.gnused}/bin/sed -i 's/^color_theme = .*/color_theme = "ficciones"/' "$conf"
      fi
    '';
  };
}
