{
  perSystem = {pkgs, ...}: {
    packages.create-project = pkgs.writeShellApplication {
      name = "create-project";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        echo "Initializing ComfyUI project in $(pwd)..."
      '';
    };
  };
}
