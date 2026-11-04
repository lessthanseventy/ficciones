# The formatters and linters menard's write check runs (Menard.Lang), on the Linux box and the
# work Mac alike: a tool missing on one host skips its check there, and its tests go red.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    shfmt
    shellcheck
    stylua
    nixfmt
    statix
    nil
  ];
}
