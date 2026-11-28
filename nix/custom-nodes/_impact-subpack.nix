{mkGithubNode, python3Packages}:
mkGithubNode {
  owner = "ltdrdata";
  repo = "ComfyUI-Impact-Subpack";
  rev = "31b729aaa8d5e5c183e2d5b942064a204eec2d34"; # 1.3.6
  hash = "sha256-/px05e4JcvhVe2DGC+6UqjbHxoA/IvB55gjKXmsDZa4=";
  dirName = "ComfyUI-Impact-Subpack";

  pythonDeps = with python3Packages; [
    ultralytics
  ];
}
