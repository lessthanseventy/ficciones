# tmux, shared by the Linux box and the work Mac (the clipboard is the only difference).
{ pkgs, ... }:

let
  copy = if pkgs.stdenv.hostPlatform.isDarwin then "pbcopy" else "wl-copy";
in
{
  # tmux — flake-managed (adopted from the standalone ~/.config/tmux/tmux.conf
  # repo): mouse, extended-keys, resurrect+continuum (ANDREW's session persistence
  # — coworkers run on their own `-L tlon-workspace-<id>` servers with a persistence-
  # free config, see Server.Profiles), yank, tmux-thumbs. No status-script chrome
  # (gitmux/cpu/battery). Old file backed up on `home:switch` via the -b flag.
  programs.tmux = {
    enable = true;
    shortcut = "b"; # Ctrl+B prefix
    escapeTime = 10;
    baseIndex = 1;
    historyLimit = 50000;
    mouse = true;
    focusEvents = true;
    terminal = "tmux-256color";
    plugins = with pkgs.tmuxPlugins; [
      resurrect
      continuum
      yank
      tmux-thumbs
    ];
    extraConfig = ''
      # Extended keys so shift+enter etc. round-trip to apps under tmux (the kitty-
      # protocol gap the worklist flagged). Apps negotiate their own encoding above this.
      # csi-u format: the most reliably decoded encoding for the agent TUIs.
      # Requires tmux 3.5+; this box runs 3.7b.
      set -s extended-keys on
      set -g extended-keys-format csi-u
      set -as terminal-features 'xterm*:extkeys'

      # Vi mode for the prompt line + copy mode.
      set -g status-keys vi
      set -g mode-keys vi
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${copy}"

      # Lean status bar — session + window tabs, NO script churn (gitmux/cpu/battery
      # dropped). Load-bearing in Tlön: this is how the coworker windows show/click.
      set -g status-position top
      set -g status-interval 15
      set -g status-left " #S "
      set -g status-right ""
      set -g window-status-current-format " #I #W "
      set -g window-status-format " #I #W "
      # Colours: the machine palette (modules/desktop/theme), never hex here —
      # the live theme's copy, so a theme switch reaches new tmux servers
      source-file ~/.config/ficciones/theme/tmux.conf

      # Splits + pane nav (prefix chords — the alt- bindings dropped, they clash with
      # terminal apps like claude/nvim and aren't worth the surface; re-add if you miss them).
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # Persistence is for ANDREW's tmux only. Coworkers (Tlön's Claude Code seats) run on
      # their own per-workspace tmux servers (tmux -L tlon-workspace-<id>, persistence-free
      # config from Server.Profiles) and come up FRESH every rebuild — agent harnesses are
      # deliberately NOT in @resurrect-processes: auto-relaunching an agent at restore
      # hands it stale identity/env (the old torn-down-coworker trap) and silently burns
      # model budget.
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
      set -g @resurrect-capture-pane-contents 'on'
      set -g @resurrect-processes 'iex mix nvim vim'

      # tmux-thumbs: hint-label copy — prefix+F fires hint labels on all visible text.
      set -g @thumbs-key F
    '';
  };
}
