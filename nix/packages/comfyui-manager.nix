{inputs, ...}: {
  perSystem = {
    system,
    pkgs,
    lib,
    ...
  }: let
    script = ./comfyui-manager.nu;

    # Prefer the CUDA build on systems where it exists, otherwise fall back to
    # the default (CPU) package.
    comfyui =
      inputs.comfyui-nix.packages.${system}.cuda
      or inputs.comfyui-nix.packages.${system}.default;

    runtimeDeps = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.fzf
      pkgs.glib
      pkgs.lsof
      pkgs.nushell
      pkgs.systemd
      pkgs.util-linux
      pkgs.xdg-utils
      (pkgs.python3.withPackages (ps: [ps.natsort]))
      comfyui
    ];

    # Install the nushell script under its final name so nushell's generated
    # help output refers to `comfyui-manager` rather than a wrapper filename.
    nuScript = pkgs.runCommandLocal "comfyui-manager-script" {} ''
      mkdir -p $out/bin
      substitute ${script} $out/bin/comfyui-manager \
        --replace-fail '#!/usr/bin/env nu' '#!${lib.getExe pkgs.nushell}'
      chmod +x $out/bin/comfyui-manager
    '';

    package =
      (pkgs.writeShellApplication {
        name = "comfyui-manager";
        runtimeInputs = runtimeDeps;
        text = ''
          export COMFYUI_MANAGER_BIN="${placeholder "out"}/bin/comfyui-manager"
          exec ${nuScript}/bin/comfyui-manager "$@"
        '';
      }).overrideAttrs (old: {
        meta =
          (old.meta or {})
          // {
            description = "Run and manage per-project ComfyUI environments";
            homepage = "https://github.com/pensive-penguin/comfyui-manager";
            license = lib.licenses.mit;
            mainProgram = "comfyui-manager";
            platforms = lib.platforms.unix;
          };
      });
  in {
    packages.comfyui-manager = package;
    packages.default = package;
  };
}
