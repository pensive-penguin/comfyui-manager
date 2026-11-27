{self, ...}: {
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

      # Previously bundled third-party nodes, pinned here so workflows keep
      # working with the nixpkgs comfyui package.
      "ComfyUI-Impact-Pack" = pkgs.fetchFromGitHub {
        owner = "ltdrdata";
        repo = "ComfyUI-Impact-Pack";
        rev = "8.28";
        hash = "sha256-V/gMPqo9Xx21+KpG5LPzP5bML9nGlHHMyVGoV+YgFWE=";
      };

      "rgthree-comfy" = pkgs.fetchFromGitHub {
        owner = "rgthree";
        repo = "rgthree-comfy";
        rev = "2c5342a8cb0eaecaabf61435a5f37dd594c510ba";
        hash = "sha256-Z3yKY+6VW5wfsOkI+LrNFd3oZMXKVITtinsNXVXFNec=";
      };

      "ComfyUI-KJNodes" = pkgs.fetchFromGitHub {
        owner = "kijai";
        repo = "ComfyUI-KJNodes";
        rev = "c9869eade9920a1b949de07c4a197156006bcceb";
        hash = "sha256-8jhXmMmIdf99bkxZjPXcorPUIpEPEIjFthSTwJUVj+Y=";
      };

      "ComfyUI-GGUF" = pkgs.fetchFromGitHub {
        owner = "city96";
        repo = "ComfyUI-GGUF";
        rev = "6ea2651e7df66d7585f6ffee804b20e92fb38b8a";
        hash = "sha256-/ZwecgxTTMo9J1whdEJci8lEkOy/yP+UmjbpOAA3BvU=";
      };

      "ComfyUI-Lora-Manager" = pkgs.fetchFromGitHub {
        owner = "willmiao";
        repo = "ComfyUI-Lora-Manager";
        rev = "21dc58fec2aab4e41deb549058253b71afa5573c"; # v1.3.0
        hash = "sha256-Lk10gZbYlD2XXzoccmBCcIBgzXAqFLArhmIZqHGInpc=";
      };

      "ComfyUI-Impact-Subpack" = pkgs.fetchFromGitHub {
        owner = "ltdrdata";
        repo = "ComfyUI-Impact-Subpack";
        rev = "31b729aaa8d5e5c183e2d5b942064a204eec2d34"; # 1.3.6
        hash = "sha256-/px05e4JcvhVe2DGC+6UqjbHxoA/IvB55gjKXmsDZa4=";
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

    enabledModules = lib.filterAttrs (_: module: module.enable) cfg.modules;
    resolvedModules = lib.mapAttrs resolveModule enabledModules;

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

          The previously bundled nodes (`ComfyUI-Impact-Pack`, `rgthree-comfy`,
          `ComfyUI-KJNodes` and `ComfyUI-GGUF`), plus `ComfyUI-Lora-Manager` and
          `ComfyUI-Impact-Subpack`, are available as built-ins, so they can be
          enabled or disabled by name just like any other module. All custom
          nodes are linked into the shared base directory with systemd-tmpfiles;
          they apply to the CLI, the DMS plugin and the optional
          `services.comfyui` service alike.
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
          These are `ComfyUI-Anima-LLLite`, `ComfyUI-Impact-Pack`, `rgthree-comfy`,
          `ComfyUI-KJNodes`, `ComfyUI-GGUF`, `ComfyUI-Lora-Manager` and
          `ComfyUI-Impact-Subpack`.
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
          Shared ComfyUI base directory whose `custom_nodes/` directory receives
          the immutable modules. When null and
          {option}`programs.comfyui-manager.user` is set, defaults to that user's
          `~/.config/comfy-ui`, matching the CLI default. When set, it is also
          exported as `COMFY_HOME` (unless overridden) and used as
          `services.comfyui.dataDir`.

          Modules are linked with `systemd-tmpfiles` using `L+`, so a declared
          module replaces any mutable directory of the same name. The source is a
          read-only Nix store path.
        '';
      };

      enableService = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Also enable nixpkgs' `services.comfyui` systemd service. It uses the
          same ComfyUI package and data directory as the CLI. Note that the
          service runs as `comfyui` by default; when the shared directory is
          owned by another user, override
          `systemd.services.comfyui.serviceConfig.User`/`Group` accordingly.
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

      # Keep the CLI's runtime base directory in sync with the directory the
      # custom-node links are created in. COMFY_HOME can still be overridden
      # by the user or by the DMS plugin.
      environment.variables = lib.optionalAttrs (installDir != null) {
        COMFY_HOME = lib.mkDefault installDir;
      };

      services.comfyui.package =
        if cfg.package.passthru ? comfyui
        then cfg.package.passthru.comfyui
        else pkgs.comfyui;
      services.comfyui.dataDir = lib.mkIf (installDir != null) installDir;
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
