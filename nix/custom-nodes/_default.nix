{pkgs, lib}:
let
  aliases = import ./_aliases.nix;

  # A plain import keeps the helper a partial function; callPackage would try
  # to apply its own auto-arguments before a node supplies owner/repo/hash.
  mkGithubNode = args:
    import ./_mk-github-node.nix ({
      inherit (pkgs) stdenv fetchFromGitHub;
      inherit lib;
    } // args);

  segment-anything = pkgs.callPackage ./_segment-anything.nix {};

  call = file: args: pkgs.callPackage file ({inherit mkGithubNode;} // args);

  canonical = {
    "anima-llllite" = call ./_anima-llllite.nix {};
    "impact-pack" = call ./_impact-pack.nix {inherit segment-anything;};
    rgthree = call ./_rgthree.nix {};
    "kj-nodes" = call ./_kj-nodes.nix {};
    gguf = call ./_gguf.nix {};
    "lora-manager" = call ./_lora-manager.nix {};
    "impact-subpack" = call ./_impact-subpack.nix {};
    "toyxyz-test-nodes" = call ./_toyxyz-test-nodes.nix {};
  };
in
canonical // lib.mapAttrs (alias: target: canonical.${target}) aliases
