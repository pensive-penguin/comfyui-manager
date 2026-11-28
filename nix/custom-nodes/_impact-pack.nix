{mkGithubNode, python3Packages, segment-anything}:
mkGithubNode {
  owner = "ltdrdata";
  repo = "ComfyUI-Impact-Pack";
  rev = "8.28";
  version = "8.28";
  hash = "sha256-V/gMPqo9Xx21+KpG5LPzP5bML9nGlHHMyVGoV+YgFWE=";
  dirName = "ComfyUI-Impact-Pack";

  pythonDeps = with python3Packages; [
    scikit-image
    piexif
    scipy
    numpy
    opencv4
    matplotlib
    dill
    sam2
    segment-anything
  ];
}
