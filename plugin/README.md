# ComfyUI DMS plugin

Composite DMS plugin for `comfyui-manager`. It provides:

- a bar widget with status and a popout for starting/stopping/restarting/switching projects,
- a background daemon that polls the CLI and owns no ComfyUI process itself,
- settings for ComfyUI home, extra project roots, base port, extra flags, and logging.

The plugin never starts ComfyUI on load and never enables a boot service. The CLI
uses a transient `systemd --user` unit only while ComfyUI is running.

## Requirements

- DMS 2.x (`requires_dms >= 2.0.0`)
- A `comfyui-manager` CLI build with the `start`, `stop`, `status`, `list`,
  `restart`, `switch`, `logs`, and `open` subcommands.

## Development install

```bash
ln -s "$PWD/plugin" ~/.config/dms/plugins/comfyuiManager
dms ipc call plugin-scan scan
dms ipc call plugins enable comfyuiManager
```

Then add the **ComfyUI** widget to a bar in DMS Settings → Appearance → Bar.

Reload while iterating:

```bash
dms ipc call plugins reload comfyuiManager
```

## NixOS module

```nix
programs.comfyui-manager = {
  enable = true;
  user = "alice";
  dmsPlugin.enable = true;
};
```

The module links the plugin into `<user home>/.config/dms/plugins/comfyuiManager`
with `systemd-tmpfiles`. Use `dmsPlugin.configDir` if your DMS config lives
elsewhere.

## IPC

```bash
dms ipc call comfyuiManager status
dms ipc call comfyuiManager list
dms ipc call comfyuiManager start '<project-id>'
dms ipc call comfyuiManager stop
dms ipc call comfyuiManager restart
dms ipc call comfyuiManager switchProject '<project-id>'
dms ipc call comfyuiManager retry
dms ipc call comfyuiManager open
dms ipc call comfyuiManager refresh
```

Project IDs are returned by `comfyui-manager list --json` and are stable across
multiple project roots.
