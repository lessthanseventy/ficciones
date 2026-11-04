# What menard runs on a host, on the Linux box and the work Mac alike: mise for the host's
# toolchain and tasks, Expert for `find`'s references (Menard.Lsp), and the formatters and linters
# of its write check (Menard.Lang). A tool missing on one host skips its check there, and its tests
# go red.
{ pkgs, expertPackages, ... }:

{
  home.packages = with pkgs; [
    expertPackages.${pkgs.stdenv.hostPlatform.system}.expert
    mise
    shfmt
    shellcheck
    stylua
    nixfmt
    statix
    nil
  ];
}
