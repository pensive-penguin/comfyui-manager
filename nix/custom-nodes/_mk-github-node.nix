{
  lib,
  stdenv,
  fetchFromGitHub,
  owner,
  repo,
  rev,
  hash,
  version ? rev,
  pname ? lib.toLower (lib.replaceStrings ["_"] ["-"] repo),
  dirName ? repo,
  patches ? [],
  pythonDeps ? [],
  description ? "ComfyUI custom node ${repo}",
  homepage ? "https://github.com/${owner}/${repo}",
  license ? null,
}:
let
  src = fetchFromGitHub {
    inherit owner repo rev hash;
  };
in
(stdenv.mkDerivation {
  inherit pname version src patches;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R ./. $out/
    runHook postInstall
  '';

  meta = lib.filterAttrs (_: value: value != null) {
    inherit description homepage license;
    platforms = lib.platforms.unix;
  };
}).overrideAttrs (old: {
  # Custom nodes are source-only packages. Their Python dependencies are
  # collected by the comfyui-manager package and added to the wrapped ComfyUI
  # environment, since that wrapper unsets PYTHONPATH.
  passthru = (old.passthru or {}) // {
    inherit pythonDeps;
    comfyuiDirName = dirName;
    github = {inherit owner repo rev;};
  };
})
