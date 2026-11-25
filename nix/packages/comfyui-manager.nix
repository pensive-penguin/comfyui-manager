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

    # comfyui-nix links its bundled third-party nodes unconditionally. This
    # wrapper keeps that behaviour, but lets `COMFYUI_DISABLED_BUNDLED_NODES`
    # (space-separated directory names) opt individual bundled nodes out at
    # launch time without touching the rest of the bundle. It keeps the
    # original passthru so it can also stand in as services.comfyui.package.
    comfyuiPatched = pkgs.runCommandLocal "comfy-ui-bundled-filter" {
      passthru = comfyui.passthru;
    } ''
      mkdir -p $out/bin
      {
        head -n 1 ${comfyui}/bin/comfy-ui
        cat <<'BUNDLED_FILTER'
link_bundled() {
  local src="$1" dest="$2" name disabled
  name="$(basename "$dest")"
  for disabled in ''${COMFYUI_DISABLED_BUNDLED_NODES:-}; do
    if [ "$name" = "$disabled" ]; then
      rm -f "$dest"
      return 0
    fi
  done
  ln -sfn "$src" "$dest"
}
BUNDLED_FILTER
        tail -n +2 ${comfyui}/bin/comfy-ui
      } > $out/bin/comfy-ui
      sed -i -E 's#^([[:space:]]*)ln -sfn ("[^"]*" "\$BASE_DIR/custom_nodes/[^"]*")#\1link_bundled \2#' $out/bin/comfy-ui
      # Fail loudly if upstream changes the launcher shape and the rewrite
      # silently no longer applies.
      grep -q 'link_bundled "/nix/store' $out/bin/comfy-ui
      chmod +x $out/bin/comfy-ui
      ln -s $out/bin/comfy-ui $out/bin/comfyui
    '';

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
      comfyuiPatched
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
          comfyui = comfyuiPatched;
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
  };
}
