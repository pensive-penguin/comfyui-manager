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

Built-in, pinned sources are available for:

- `ComfyUI-Anima-LLLite`
- `ComfyUI-Impact-Pack`
- `rgthree-comfy`
- `ComfyUI-KJNodes`
- `ComfyUI-GGUF`

Enable them with empty attribute sets, or disable one with `enable = false`:

```nix
programs.comfyui-manager = {
  enable = true;
  user = "alice";
  modules = {
    "ComfyUI-Impact-Pack" = {};
    "rgthree-comfy" = {};
    "ComfyUI-KJNodes" = {};
    "ComfyUI-GGUF" = {};
  };
};
```

Their Python dependencies are included in ComfyUI's wrapped environment via
`extraPackages`. `segment_anything` is built locally because nixpkgs does not
package it.

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
