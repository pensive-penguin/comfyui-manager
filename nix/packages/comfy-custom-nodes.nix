{...}: {
  perSystem = {
    lib,
    pkgs,
    ...
  }: let
    customNodes = import ../custom-nodes/_default.nix {inherit lib pkgs;};
  in {
    # flake-parts' `packages` is flat (`attrsOf package`); legacyPackages is
    # the supported place for a nested package namespace.
    legacyPackages.comfyCustomNodes = customNodes;
  };
}
