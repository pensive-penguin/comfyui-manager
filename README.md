# comfyui-manager

A Nushell CLI and DankMaterialShell plugin for running ComfyUI against
per-project directories, plus a NixOS module for declaratively linking custom
nodes into ComfyUI's base directory.

ComfyUI itself comes from nixpkgs-unstable's `pkgs.comfyui` package. The flake
enables CUDA-backed PyTorch on `x86_64-linux`; other systems use CPU-only
PyTorch. The `cache.nixos-cuda.org` substituter is configured and the CUDA EULA
packages are allowed for those builds.

## Data directory

The CLI uses `$COMFY_HOME`, defaulting to `~/.config/comfy-ui`. The NixOS module
exports the same value as `COMFY_HOME` when `user` or `installTo` is set, and
points `services.comfyui.dataDir` at it. Custom nodes declared through
`programs.comfyui-manager.modules` are symlinked into
`<dataDir>/custom_nodes` with systemd-tmpfiles.

## Custom nodes

Pinned custom-node packages are available as flake outputs under
`legacyPackages.<system>.comfyCustomNodes` (e.g.
`nix build .#legacyPackages.x86_64-linux.comfyCustomNodes.toyxyz-test-nodes`).
Canonical names are:

- `anima-llllite`
- `impact-pack`
- `rgthree`
- `kj-nodes`
- `gguf`
- `lora-manager`
- `impact-subpack`
- `toyxyz-test-nodes` (Linux-patched)

Upstream directory names and the lowercase `comfyui_toyxyz_test_nodes` are
accepted as aliases in the NixOS module. All of them opt in explicitly; the
`nixosModules.maximal` preset enables every built-in for an opt-out style:

```nix
programs.comfyui-manager = {
  enable = true;
  user = "alice";
  modules = {
    "impact-pack".enable = true;
    "toyxyz-test-nodes".enable = true;

    # Aliases also work:
    "ComfyUI-KJNodes".enable = true;
  };
};
```

For the old opt-out behavior, import
`inputs.comfyui-manager.nixosModules.maximal` instead.

Node packages can be overridden directly:

```nix
programs.comfyui-manager.modules."impact-pack".package =
  inputs.comfyui-manager.legacyPackages.x86_64-linux.comfyCustomNodes.impact-pack.overrideAttrs {
    patches = [ ./my-impact-fix.patch ];
  };
```

Each node package declares its Python dependencies through `passthru.pythonDeps`;
they are collected into ComfyUI's wrapped `extraPackages` environment.
`segment_anything` is built locally because nixpkgs does not package it.

`toyxyz-test-nodes` is patched for this unix/NixOS build in
`nix/patches/comfyui-toyxyz-linux.patch`. Upstream imports `win32*` and
`ctypes.windll`/`wintypes` at module load time, but `pywin32` is Windows-only
and `sys.platform` is never `"win32"` here; those imports are removed rather
than guarded. `cv2.CAP_DSHOW` is also replaced with the portable OpenCV
backend. The pack and all its nodes load normally. `CaptureWebcam` works with
the default camera backend, and `Direct Screen Capture` works in its `Default`
mode; its `window` and `window_crop` modes remain unavailable because they need
Windows window APIs.

## Migrating from comfyui-nix

The old launcher symlinked bundled nodes on every start. Those symlinks can be
removed once from the shared data directory:

```sh
find "${COMFY_HOME:-$HOME/.config/comfy-ui}/custom_nodes" -maxdepth 1 -type l -lname '/nix/store/*' -delete
```

Back up `user/default/workflows` and `user/comfyui.db` before the first run on
ComfyUI 0.45.x. Project inputs, outputs, models and workflows otherwise stay in
the same directory because the CLI passes `--base-directory` explicitly.

## Development

```sh
nix flake check
nix build .#comfyui-manager
nix run .#comfyui-manager -- --help
```
