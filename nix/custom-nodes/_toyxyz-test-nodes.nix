{mkGithubNode, python3Packages}:
mkGithubNode {
  owner = "toyxyz";
  repo = "ComfyUI_toyxyz_test_nodes";
  rev = "8291d9b65d56d65be55ee0f31df073d42b7d0eb6";
  version = "1.0.6";
  hash = "sha256-vwmcIM7TjvJ4HAYsCPg/1qa52d+K+1P5DgWbDx4/1FI=";
  dirName = "ComfyUI_toyxyz_test_nodes";

  # Upstream imports win32* / ctypes.windll unconditionally. This flake targets
  # unix, where those imports cannot work and pywin32 is not available, so a
  # sys.platform guard would be dead code. The patch drops the imports and
  # switches CAP_DSHOW to a portable backend instead. Direct Screen Capture's
  # window/window_crop modes remain unavailable.
  patches = [../patches/comfyui-toyxyz-linux.patch];

  pythonDeps = with python3Packages; [
    av
    einops
    trimesh
    rapidfuzz
    torchaudio
    huggingface-hub
    imageio-ffmpeg
    psutil
    mss
    numpy
    opencv4
  ];
}
