# Dependency of ComfyUI-Impact-Pack; nixpkgs does not package it yet.
{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonPackage {
  pname = "segment-anything";
  version = "1.0";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "segment-anything";
    rev = "dca509fe793f601edb92606367a655c15ac00fdf";
    hash = "sha256-28XHhv/hffVIpbxJKU8wfPvDB63l93Z6r9j1vBOz/P0=";
  };

  nativeBuildInputs = with python3Packages; [setuptools wheel];

  propagatedBuildInputs = with python3Packages; [
    torch
    torchvision
    numpy
    opencv4
    matplotlib
    pillow
  ];

  doCheck = false;
  pythonImportsCheck = ["segment_anything"];

  meta = {
    description = "Segment Anything Model (SAM) from Meta AI";
    homepage = "https://github.com/facebookresearch/segment-anything";
    license = lib.licenses.asl20;
  };
}
