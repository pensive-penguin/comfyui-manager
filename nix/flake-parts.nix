{inputs, ...}: {
  config = {
    systems = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];

    perSystem = {
      system,
      ...
    }: {
      # nixpkgs' comfyui package uses python3Packages.torch, which honours this
      # config option. Without it ComfyUI would silently fall back to CPU-only
      # torch instead of the CUDA build used previously via comfyui-nix.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          cudaSupport = system == "x86_64-linux";
          allowUnfree = true;
        };
      };
    };
  };
}
