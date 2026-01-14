{
  description = "A project-based wrapper for ComfyUI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://comfyui.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  outputs = {
    self,
    nixpkgs,
    comfyui-nix,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
      comfy-pkg = comfyui-nix.packages.${system}.cuda;
    in {
      create-project = pkgs.callPackage ./packages/create-project.nix {inherit pkgs;};
      run-project = pkgs.callPackage ./packages/run-project.nix {inherit pkgs comfy-pkg;};
      default = self.packages.${system}.run-project;
    });

    # Allows you to use `nix run .#create-project`
    apps = forAllSystems (system: {
      create-project = {
        type = "app";
        program = "${self.packages.${system}.create-project}/bin/create-project";
      };
      run-project = {
        type = "app";
        program = "${self.packages.${system}.run-project}/bin/run-project";
      };
    });
  };
}
