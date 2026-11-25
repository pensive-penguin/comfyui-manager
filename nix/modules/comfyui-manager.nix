{inputs, self, ...}: {
  flake.nixosModules.comfyui-manager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.programs.comfyui-manager;

    inherit (lib) mkEnableOption mkOption literalExpression types;

    fetchGitType = types.submodule {
      options = {
        url = mkOption {
          type = types.str;
          description = "Git repository URL.";
        };

        rev = mkOption {
          type = types.str;
          description = "Git revision (commit, tag or branch). A full commit hash is recommended.";
        };

        hash = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Source hash, in SRI (`sha256-...`) or base32 form. Without a hash,
            evaluation falls back to `builtins.fetchGit`, which is pinned by
            `rev` but cannot be verified against a hash.
          '';
        };

        fetchSubmodules = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to fetch git submodules.";
        };
      };
    };

    moduleType = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to install this module.";
        };

        src = mkOption {
          type = types.nullOr types.package;
          default = null;
          description = ''
            Source of the module. Usually the result of `fetchFromGitHub`,
            `fetchGit` or another derivation containing a ComfyUI custom node.
          '';
        };

        fetchGit = mkOption {
          type = types.nullOr fetchGitType;
          default = null;
          description = ''
            Convenience alternative to {option}`programs.comfyui-manager.modules.<name>.src`
            for modules hosted in a git repository.
          '';
        };
      };
    };

    builtinModules = {
      ComfyUI-Anima-LLLite = pkgs.fetchFromGitHub {
        owner = "kohya-ss";
        repo = "ComfyUI-Anima-LLLite";
        rev = "b7495bd8eb876e334509976896702484ed19cdbb";
        hash = "sha256-g6mrJiium79O9+mQUaLCJ6z0IkGnu3G+jBfaMrBkao8=";
      };
    };

    resolveModule = name: module:
      if module.src != null
      then module.src
      else if module.fetchGit != null
      then
        if module.fetchGit.hash != null
        then
          pkgs.fetchgit {
            inherit (module.fetchGit) url rev hash fetchSubmodules;
          }
        else
          builtins.fetchGit {
            inherit (module.fetchGit) url rev;
            submodules = module.fetchGit.fetchSubmodules;
          }
      else if builtins.hasAttr name builtinModules
      then builtins.getAttr name builtinModules
      else
        throw ''
          programs.comfyui-manager.modules.${name}: no `src` or `fetchGit` was given,
          and `${name}` is not a built-in module.
          Built-in modules: ${lib.concatStringsSep ", " (builtins.attrNames builtinModules)}
        '';

    # Third-party nodes that the comfyui-nix package links into
    # custom_nodes/ by default. Setting modules.<name>.enable = false for one
    # of these turns the bundled link off instead of trying to install it.
    bundledNodeDirs = [
      "ComfyUI-Impact-Pack"
      "rgthree-comfy"
      "ComfyUI-KJNodes"
      "ComfyUI-GGUF"
      "ComfyUI-LTXVideo"
      "ComfyUI-Florence2"
      "ComfyUI_bitsandbytes_NF4"
      "x-flux-comfyui"
      "ComfyUI-MMAudio"
      "PuLID_ComfyUI"
      "ComfyUI-WanVideoWrapper"
    ];

    enabledModules = lib.filterAttrs (
      name: module: module.enable && !(builtins.elem name bundledNodeDirs)
    ) cfg.modules;
    resolvedModules = lib.mapAttrs resolveModule enabledModules;

    disabledBundledNodes =
      builtins.filter (
        name: builtins.hasAttr name cfg.modules && !cfg.modules.${name}.enable
      )
      bundledNodeDirs;

    disabledBundledNodesEnv = lib.concatStringsSep " " disabledBundledNodes;

    userHome =
      if cfg.user != null && builtins.hasAttr cfg.user config.users.users
      then config.users.users.${cfg.user}.home
      else null;

    # Matches the base directory used by `comfyui-manager run`.
    installDir =
      if cfg.installTo != null
      then cfg.installTo
      else if userHome != null
      then "${userHome}/.config/comfy-ui"
      else null;

    owner =
      if cfg.user != null
      then cfg.user
      else "root";

    group =
      if cfg.group != null
      then cfg.group
      else if cfg.user != null
      then
        (
          let
            userGroup = config.users.users.${cfg.user}.group;
          in
            if userGroup == ""
            then "users"
            else userGroup
        )
      else "root";

    dmsUser =
      if cfg.dmsPlugin.user != null
      then cfg.dmsPlugin.user
      else cfg.user;

    dmsUserHome =
      if dmsUser != null && builtins.hasAttr dmsUser config.users.users
      then config.users.users.${dmsUser}.home
      else null;

    dmsConfigDir =
      if cfg.dmsPlugin.configDir != null
      then cfg.dmsPlugin.configDir
      else if dmsUserHome != null
      then "${dmsUserHome}/.config/dms"
      else null;

    dmsOwner =
      if dmsUser != null
      then dmsUser
      else "root";

    dmsGroup =
      if dmsUser != null && builtins.hasAttr dmsUser config.users.users
      then
        (
          let
            userGroup = config.users.users.${dmsUser}.group;
          in
            if userGroup == ""
            then "users"
            else userGroup
        )
      else "root";
  in {
    imports = [inputs.comfyui-nix.nixosModules.default];

    options.programs.comfyui-manager = {
      enable = mkEnableOption "the comfyui-manager CLI and declarative ComfyUI modules";

      package = mkOption {
        type = types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.comfyui-manager;
        defaultText = literalExpression "comfyui-manager.packages.\${system}.comfyui-manager";
        description = "The comfyui-manager package to install.";
      };

      modules = mkOption {
        type = types.attrsOf moduleType;
        default = {};
        description = ''
          Declarative ComfyUI modules (custom nodes) installed immutably from the
          Nix store. The attribute name becomes the directory name under
          `custom_nodes/`.

          A module can provide {option}`programs.comfyui-manager.modules.<name>.src`,
          {option}`programs.comfyui-manager.modules.<name>.fetchGit`, or neither to
          select a built-in module by name. Set `enable = false` to disable an
          entry without removing it.

          The third-party nodes bundled by comfyui-nix can be turned off the
          same way. Recognised names: `ComfyUI-Impact-Pack`, `rgthree-comfy`,
          `ComfyUI-KJNodes`, `ComfyUI-GGUF`, `ComfyUI-LTXVideo`,
          `ComfyUI-Florence2`, `ComfyUI_bitsandbytes_NF4`, `x-flux-comfyui`,
          `ComfyUI-MMAudio`, `PuLID_ComfyUI` and `ComfyUI-WanVideoWrapper`.

          Bundled nodes are linked by the comfyui-nix launcher, so this applies
          to processes started by `comfyui-manager` (including the DMS plugin).
          For the `services.comfyui` service, use its own
          `services.comfyui.bundledCustomNodes` option instead.
        '';
        example = literalExpression ''
          {
            ComfyUI-Anima-LLLite = {}; # built-in

            my-node = {
              fetchGit = {
                url = "https://github.com/example/my-node";
                rev = "0123456789abcdef0123456789abcdef01234567";
                hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              };
            };
          }
        '';
      };

      builtinModules = mkOption {
        type = types.attrsOf types.package;
        default = builtinModules;
        readOnly = true;
        description = ''
          Modules that can be selected by name in
          {option}`programs.comfyui-manager.modules` without providing a source.
          Currently this includes `ComfyUI-Anima-LLLite`.
        '';
      };

      user = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "alice";
        description = ''
          User whose ComfyUI data directory receives the immutable modules. When
          set, the default install location is `~/.config/comfy-ui`, matching the
          directory used by `comfyui-manager run`. Ignored when
          {option}`programs.comfyui-manager.installTo` is set.
        '';
      };

      group = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "users";
        description = ''
          Group that owns the generated `custom_nodes` directory. Defaults to the
          selected user's primary group when {option}`programs.comfyui-manager.user`
          is set, and to `root` otherwise.
        '';
      };

      installTo = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/home/alice/.config/comfy-ui";
        description = ''
          ComfyUI base directory whose `custom_nodes/` directory receives the
          immutable modules. When null and {option}`programs.comfyui-manager.user`
          is set, defaults to that user's `~/.config/comfy-ui`.

          Modules are linked with `systemd-tmpfiles` using `L+`, so a declared
          module replaces any mutable directory of the same name. The source is a
          read-only Nix store path.
        '';
      };

      enableService = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Also enable the `services.comfyui` systemd service from comfyui-nix.
          Declared modules are added to `services.comfyui.customNodes` whether or
          not the service is enabled.
        '';
      };

      dmsPlugin = mkOption {
        type = types.submodule {
          options = {
            enable = mkEnableOption "the ComfyUI plugin for DankMaterialShell";

            user = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                User whose DMS configuration should receive the plugin. Defaults
                to {option}`programs.comfyui-manager.user`.
              '';
            };

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.comfyui-manager-plugin;
              defaultText = literalExpression ''
                comfyui-manager.packages.''${system}.comfyui-manager-plugin
              '';
              description = "The DMS plugin package to link into the user's DMS configuration.";
            };

            configDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "/home/alice/.config/dms";
              description = ''
                DMS configuration directory. Defaults to
                `<user home>/.config/dms` when the selected user is known.
              '';
            };
          };
        };
        default = {};
        description = ''
          Install the DMS plugin declaratively by linking it into the selected
          user's `dms/plugins` directory.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.user == null || builtins.hasAttr cfg.user config.users.users;
          message = "programs.comfyui-manager.user refers to a user that is not defined.";
        }
        {
          assertion = !cfg.dmsPlugin.enable || dmsUser != null;
          message = "programs.comfyui-manager.dmsPlugin.enable requires dmsPlugin.user or programs.comfyui-manager.user.";
        }
        {
          assertion = !cfg.dmsPlugin.enable || dmsConfigDir != null;
          message = "programs.comfyui-manager.dmsPlugin.enable requires a known DMS config directory.";
        }
      ];

      environment.systemPackages = [cfg.package];

      environment.variables = lib.optionalAttrs (disabledBundledNodes != []) {
        COMFYUI_DISABLED_BUNDLED_NODES = lib.mkDefault disabledBundledNodesEnv;
      };

      services.comfyui.customNodes = resolvedModules;
      services.comfyui.enable = lib.mkIf cfg.enableService true;

      systemd.tmpfiles.rules =
        lib.optionals (installDir != null) (
          [
            "d ${installDir}/custom_nodes 0755 ${owner} ${group} -"
          ]
          ++ lib.mapAttrsToList (
            name: source: "L+ ${installDir}/custom_nodes/${name} - - - - ${source}"
          )
          resolvedModules
        )
        ++ lib.optionals (cfg.dmsPlugin.enable && dmsConfigDir != null) [
          "d ${dmsConfigDir} 0755 ${dmsOwner} ${dmsGroup} -"
          "d ${dmsConfigDir}/plugins 0755 ${dmsOwner} ${dmsGroup} -"
          "L+ ${dmsConfigDir}/plugins/comfyuiManager - - - - ${cfg.dmsPlugin.package}/share/dms/plugins/comfyuiManager"
        ];
    };
  };

  flake.nixosModules.default = self.nixosModules.comfyui-manager;
}
