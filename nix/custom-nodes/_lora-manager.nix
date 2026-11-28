{mkGithubNode, python3Packages}:
mkGithubNode {
  owner = "willmiao";
  repo = "ComfyUI-Lora-Manager";
  rev = "21dc58fec2aab4e41deb549058253b71afa5573c"; # v1.3.0
  hash = "sha256-Lk10gZbYlD2XXzoccmBCcIBgzXAqFLArhmIZqHGInpc=";
  dirName = "ComfyUI-Lora-Manager";

  pythonDeps = with python3Packages; [
    aiohttp
    aiohttp-socks
    jinja2
    safetensors
    olefile
    toml
    gitpython
    aiosqlite
    beautifulsoup4
    platformdirs
    pyyaml
    brotli
  ];
}
