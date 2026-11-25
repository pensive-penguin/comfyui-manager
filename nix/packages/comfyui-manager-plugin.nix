{self, ...}: {
  perSystem = {
    pkgs,
    ...
  }: let
    plugin = pkgs.runCommandLocal "comfyui-manager-plugin" {} ''
      mkdir -p $out/share/dms/plugins
      cp -r ${../../plugin} $out/share/dms/plugins/comfyuiManager
    '';
  in {
    packages.comfyui-manager-plugin =
      plugin.overrideAttrs (old: {
        meta =
          (old.meta or {})
          // {
            description = "DMS plugin for comfyui-manager";
            homepage = "https://github.com/pensive-penguin/comfyui-manager";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
          };
      });
  };
}
