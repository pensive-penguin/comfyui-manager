{self, ...}: {
  perSystem = {
    system,
    pkgs,
    lib,
    ...
  }: let
    script = ./comfyui-manager.nu;
    comfyCustomNodes = self.legacyPackages.${system}.comfyCustomNodes;

    # The nixpkgs comfyui wrapper unsets PYTHONPATH, so custom-node imports
    # must be part of the wrapped Python environment instead of injected at
    # launch time. Each node package declares its own deps via passthru.
    nodeDeps = lib.unique (
      lib.concatMap (node: node.passthru.pythonDeps or []) (lib.attrValues comfyCustomNodes)
    );

    comfyuiExtraPackages = ps:
      with ps;
      [
        comfyui-manager
        natsort
      ]
      ++ nodeDeps;

    comfyui = pkgs.comfyui.override {extraPackages = comfyuiExtraPackages;};

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
        passthru = (old.passthru or {}) // {
          comfyui = comfyui;
          comfyuiExtraPackages = comfyuiExtraPackages;
        };
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

    checks.comfyui-manager-help = pkgs.runCommand "comfyui-manager-help" {} ''
      ${lib.getExe package} --help > $out
    '';
  };
}
