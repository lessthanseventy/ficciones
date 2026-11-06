# tmux, shared by the Linux box and the work Mac (the clipboard is the only difference).
{ pkgs, ... }:

let
  copy = if pkgs.stdenv.hostPlatform.isDarwin then "pbcopy" else "wl-copy";
  # not in nixpkgs; needs fzf, zoxide and fd on PATH
  tmux-tea = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tea";
    version = "0-unstable-2026-10-24";
    src = pkgs.fetchFromGitHub {
      owner = "2kabhishek";
      repo = "tmux-tea";
      rev = "ff3316561d382cb1df9c319577939e8df39b74ad";
      hash = "sha256-0OOlhIS1bOAooamMTK4EUnQSaj1MCSjfB3DhqvNfPJA=";
    };
  };
in
{
  # tmux — flake-managed (adopted from the standalone ~/.config/tmux/tmux.conf
  # repo): mouse, extended-keys, resurrect+continuum (ANDREW's session persistence
  # — coworkers run on their own `-L tlon-workspace-<id>` servers with a persistence-
  # free config, see Server.Profiles), yank, tmux-thumbs, tmux-fzf, tmux-tea. No status-script chrome
  # (gitmux/cpu/battery). Old file backed up on `home:switch` via the -b flag.
  programs.tmux = {
    enable = true;
    shortcut = "b"; # Ctrl+B prefix
    escapeTime = 10;
    baseIndex = 1;
    historyLimit = 50000;
    mouse = true;
    focusEvents = true;
    aggressiveResize = true;
    terminal = "tmux-256color";
    # A plugin reads its options when it loads, so they sit in its own extraConfig, which
    # home-manager writes before the plugin's run-shell; the module's extraConfig comes after.
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-processes 'iex mix nvim vim'
        '';
      }
      {
        # Persistence is for ANDREW's tmux only. Coworkers (Tlön's Claude Code seats) run on
        # their own per-workspace tmux servers (tmux -L tlon-workspace-<id>, persistence-free
        # config from Server.Profiles) and come up FRESH every rebuild — agent harnesses are
        # deliberately NOT in @resurrect-processes: auto-relaunching an agent at restore
        # hands it stale identity/env and silently burns model budget.
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
      yank
      {
        plugin = tmux-thumbs;
        extraConfig = "set -g @thumbs-key F";
      }
      {
        # prefix+f: fuzzy-find sessions, windows, panes and commands (stock find-window, upgraded)
        plugin = tmux-fzf;
        extraConfig = ''set-environment -g TMUX_FZF_LAUNCH_KEY "f"'';
      }
      {
        # prefix+t: jump to a session, or open one on a repo or zoxide directory
        plugin = tmux-tea;
        extraConfig = ''
          set -g @tea-alt-bind 'false'
          set -g @tea-find-path '~/projects'
        '';
      }
    ];
    extraConfig = ''
      # The nix profile on the server's PATH, whatever shell started it: a command a window runs
      # directly (pram's `claude`) gets this environment and no shell rc, so without it a server
      # started before the profile existed hides mise and menard's tools for as long as it runs.
      %if "#{!=:#{m:*:$HOME/.nix-profile/bin:*,:$PATH:},1}"
      set-environment -g PATH "$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      %endif

      # Extended keys so shift+enter etc. round-trip to apps under tmux (the kitty-
      # protocol gap the worklist flagged). Apps negotiate their own encoding above this.
      # csi-u format: the most reliably decoded encoding for the agent TUIs.
      # Requires tmux 3.5+; this box runs 3.7b.
      set -s extended-keys on
      set -g extended-keys-format csi-u
      set -as terminal-features 'xterm*:extkeys'

      set -g status-keys emacs
      set -g mode-keys vi
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${copy}"

      # Lean status bar — session + window tabs, NO script churn (gitmux/cpu/battery
      # dropped). Load-bearing in Tlön: this is how the coworker windows show/click.
      set -g status-position top
      set -g status-interval 15
      set -g status-justify absolute-centre
      set -g window-status-separator ""
      set -g status-left-length 40
      set -g status-left "#{?client_prefix,#[reverse],} #S #[default]"
      set -g status-right ""
      set -g window-status-current-format " #I #W#{?window_zoomed_flag, Z,} "
      set -g window-status-format " #I #W#{?window_zoomed_flag, Z,} "
      set -g display-time 4000

      set -g renumber-windows on
      set -g allow-rename off
      set -g set-titles on
      set -g set-titles-string "#S · #W"
      # Claude Code's process title is its version number (2.1.319); name the window for it.
      set -g automatic-rename-format "#{?#{m/r:^[0-9.]+$,#{pane_current_command}},claude,#{pane_current_command}}#{?pane_dead,[dead],}"
      # Colours: the machine palette (modules/desktop/theme), never hex here —
      # the live theme's copy, so a theme switch reaches new tmux servers
      source-file ~/.config/ficciones/theme/tmux.conf

      bind c new-window -c "#{pane_current_path}"
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind -r S-Left resize-pane -L 2
      bind -r S-Down resize-pane -D 2
      bind -r S-Up resize-pane -U 2
      bind -r S-Right resize-pane -R 2
      bind C-p previous-window
      bind C-n next-window
      bind L switch-client -l
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # Root-table keys reach no app underneath, so only these Alt chords (they clash with
      # nvim/claude otherwise) and the F-keys, which ghostty sends for cmd+1…9 on the Mac.
      bind -n M-h previous-window
      bind -n M-l next-window
      bind -n M-H swap-window -t -1
      bind -n M-L swap-window -t +1
      bind -n M-x confirm-before -p "kill #W? (y/n)" kill-window
      bind -n F1 select-window -t 1
      bind -n F2 select-window -t 2
      bind -n F3 select-window -t 3
      bind -n F4 select-window -t 4
      bind -n F5 select-window -t 5
      bind -n F6 select-window -t 6
      bind -n F7 select-window -t 7
      bind -n F8 select-window -t 8
      bind -n F9 select-window -t 9
    '';
  };
}
