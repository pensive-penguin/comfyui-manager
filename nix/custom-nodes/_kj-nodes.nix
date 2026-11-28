{mkGithubNode, python3Packages}:
mkGithubNode {
  owner = "kijai";
  repo = "ComfyUI-KJNodes";
  rev = "c9869eade9920a1b949de07c4a197156006bcceb";
  hash = "sha256-8jhXmMmIdf99bkxZjPXcorPUIpEPEIjFthSTwJUVj+Y=";
  dirName = "ComfyUI-KJNodes";

  pythonDeps = with python3Packages; [
    color-matcher
    mss
  ];
}
