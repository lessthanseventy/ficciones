# ivysaur — the laptop, as NixOS. i7-13700H + Iris Xe (primary) + RTX 4060 Max-Q (PRIME
# offload), btrfs on nvme0n1p2 with the Garuda subvolume layout kept as-is, the ESP at
# /boot/efi. Everything Hyprland/shell/font comes from ./default.nix; this file is the hardware,
# the disks, and what the machine additionally runs (steam, snapper on /home, nix-ld).
#
# Facts captured from the live Arch install on 2026-09-05 (lsblk, findmnt, lspci, /etc/hosts):
# see docs/plans/2026-09-05-ivysaur-nixos-migration-runbook.md. NOT yet installed anywhere —
# `nix build .#nixosConfigurations.ivysaur.config.system.build.toplevel` is the gate.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  btrfs = subvol: {
    device = "/dev/disk/by-uuid/b0077b04-b5d9-4693-9043-b46b7b28f42f";
    fsType = "btrfs";
    options = [ "subvol=${subvol}" "noatime" "compress=zstd:3" "ssd" "discard=async" "space_cache=v2" ];
  };
in
{
  networking.hostName = "ivysaur";
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---- boot -------------------------------------------------------------------------------
  # GRUB, not systemd-boot: the ESP is 300 MB (Garuda's), too small to hold kernels for a useful
  # number of generations. GRUB keeps them in /boot on the btrfs root subvolume.
  boot.loader = {
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      configurationLimit = 20;
    };
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot/efi";
  };
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.supportedFilesystems = [ "btrfs" ];
  # The Arch cmdline, minus the bits NixOS derives (root, resume, rootflags).
  boot.kernelParams = [ "quiet" "loglevel=3" "pcie_aspm=force" "intel_pstate=passive" "mem_sleep_default=deep" ];
  boot.resumeDevice = "/dev/disk/by-uuid/dbc5438c-46d0-41b5-9530-2f4e0e907ed8";

  # ---- disks: the Garuda layout, unchanged ------------------------------------------------
  fileSystems = {
    "/" = btrfs "@";
    "/home" = btrfs "@home";
    "/root" = btrfs "@root";
    "/srv" = btrfs "@srv";
    "/var/cache" = btrfs "@cache";
    "/var/log" = btrfs "@log";
    "/var/tmp" = btrfs "@tmp";
    "/boot/efi" = {
      device = "/dev/disk/by-uuid/AF10-16B1";
      fsType = "vfat";
      options = [ "umask=0077" "noatime" ];
    };
  };
  swapDevices = [ { device = "/dev/disk/by-uuid/dbc5438c-46d0-41b5-9530-2f4e0e907ed8"; } ];
  boot.tmp.useTmpfs = true;

  # snapper for /home only — NixOS generations cover /. Same lever as Garuda's /.snapshots.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "andrew" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 12;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 2;
    TIMELINE_LIMIT_YEARLY = 0;
  };
  services.btrfs.autoScrub = { enable = true; interval = "monthly"; };
  services.fstrim.enable = true;

  # ---- graphics: Intel primary, NVIDIA on PRIME offload (EnvyControl "hybrid" mode) ---------
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # steam / wine
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true; # nvidia-open on Arch today (the same modules)
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true; # NVreg_DynamicPowerManagement=0x02, as EnvyControl set
    nvidiaSettings = false;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # nvidia-offload <cmd> (was steam-nvidia / prime-run)
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  # nvidia-smi 1.8s/call is why the shell polls GPU every 5s; nvtop for the rest.
  environment.systemPackages = with pkgs; [
    nvtopPackages.full
    powertop
    btrfs-progs
    snapper
    # Everything hyprland.lua binds or the shell execs, that ./default.nix does not already carry.
    grim slurp swappy hyprshot hyprpicker tesseract playerctl brightnessctl
    easyeffects xdg-user-dirs khal
    kdePackages.dolphin kdePackages.kate pavucontrol
    # terminals + TUIs the palette themes
    kitty wezterm btop lazygit bat fzf cava delta diff-so-fancy starship neovim
    # GTK/Qt looks (modules/desktop/theme names these)
    (catppuccin-gtk.override { variant = "mocha"; accents = [ "yellow" ]; })
    papirus-icon-theme bibata-cursors
    kdePackages.qt6ct libsForQt5.qt5ct kdePackages.qtstyleplugin-kvantum
    # daily apps (the Arch profile; see the runbook §"what has no twin")
    # rustdesk builds from source (a full Rust compile) — runbook §5 TODO, not worth the build
    zoom-us vesktop signal-desktop slack obsidian libreoffice-fresh mpv imv
    bitwarden-desktop rbw qbittorrent telegram-desktop
    ripgrep eza zoxide atuin tmuxinator
    podman-compose
  ];

  # ---- games ------------------------------------------------------------------------------
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;

  # ---- network ----------------------------------------------------------------------------
  # networking.networkmanager is on in ./default.nix.
  networking.extraHosts = ''
    127.0.0.1 appcount.appr admin.appcount.appr application.appcount.appr residents.appcount.appr management.appcount.appr maintenance.appcount.appr
  '';
  services.tailscale.enable = true;
  # the rail's VPN card drives the mullvad CLI (shell/lib/vpn.ts); it is in daily use on Arch
  services.mullvad-vpn.enable = true;   # the daemon + CLI; no GUI (the card is the GUI)
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  services.openssh.enable = true;
  services.printing.enable = true;
  services.avahi = { enable = true; nssmdns4 = true; };
  services.fwupd.enable = true;
  services.thermald.enable = true;
  services.power-profiles-daemon.enable = true; # the shell's BAT popover drives it

  # ---- dev services the Arch box runs from pacman (survey 2026-09-07) ---------------------------
  # podman with the docker CLI shim (pacman: podman + podman-docker + podman-compose; oxker,
  # lazydocker and podman-desktop in modules/desktop sit on top)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  # postgres 18 with the two extensions the Arch box carries (pgvector, timescaledb); the data
  # dir is fresh on a new box — dump/restore from Arch is a runbook step, not a nix one
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    extensions = ps: with ps; [ pgvector timescaledb ];
    settings.shared_preload_libraries = [ "timescaledb" ];
  };

  # ---- login: greetd → uwsm → Hyprland (the VM autologs in; the laptop asks) ----------------
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start -- hyprland-uwsm.desktop'";
      user = "greeter";
    };
  };

  # Qt through qt6ct + kvantum here (the Arch box never had them; modules/desktop defaults to gtk3).
  home-manager.users.andrew.ficciones.desktop.theme.qtPlatformTheme = "qt6ct";
  home-manager.users.andrew.ficciones.desktop.host = "ivysaur";

  # /etc/hosts also needs "127.0.1.1 ivysaur"; networking.hostName provides it.
  system.stateVersion = "25.11";
}
