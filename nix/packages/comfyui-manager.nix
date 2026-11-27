{...}: {
  perSystem = {
    system,
    pkgs,
    lib,
    ...
  }: let
    script = ./comfyui-manager.nu;

    # Impact Pack needs `segment_anything`, which is still not packaged in
    # nixpkgs. Build it here; everything else comes from python3Packages.
    segment-anything = pkgs.python3Packages.buildPythonPackage {
      pname = "segment-anything";
      version = "1.0";
      format = "pyproject";

      src = pkgs.fetchFromGitHub {
        owner = "facebookresearch";
        repo = "segment-anything";
        rev = "dca509fe793f601edb92606367a655c15ac00fdf";
        hash = "sha256-28XHhv/hffVIpbxJKU8wfPvDB63l93Z6r9j1vBOz/P0=";
      };

      nativeBuildInputs = with pkgs.python3Packages; [setuptools wheel];

      propagatedBuildInputs = with pkgs.python3Packages; [
        torch
        torchvision
        numpy
        opencv4
        matplotlib
        pillow
      ];

      doCheck = false;
      pythonImportsCheck = ["segment_anything"];

      meta = {
        description = "Segment Anything Model (SAM) from Meta AI";
        homepage = "https://github.com/facebookresearch/segment-anything";
        license = lib.licenses.asl20;
      };
    };

    # The nixpkgs comfyui wrapper unsets PYTHONPATH, so custom-node imports
    # must be part of the wrapped Python environment instead of injected at
    # launch time.
    comfyuiExtraPackages = ps:
      with ps;
      [
        comfyui-manager
        natsort

        # ComfyUI-Impact-Pack
        scikit-image
        piexif
        scipy
        numpy
        opencv4
        matplotlib
        dill
        segment-anything
        sam2

        # ComfyUI-KJNodes
        color-matcher
        mss

        # ComfyUI-GGUF
        gguf
        sentencepiece
        protobuf

        # ComfyUI-Lora-Manager
        aiohttp
        aiohttp-socks
        jinja2
        safetensors
        olefile
        toml
        gitpython
        aiosqlite
        beautifulsoup4
        platformdirs
        pyyaml
        brotli

        # ComfyUI-Impact-Subpack
        ultralytics

        # ComfyUI_toyxyz_test_nodes (Linux-patched)
        av
        einops
        trimesh
        rapidfuzz
        torchaudio
        huggingface-hub
        imageio-ffmpeg
        psutil
      ];

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
