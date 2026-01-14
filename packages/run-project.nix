{
  pkgs,
  comfy-pkg,
  ...
}:
pkgs.writeShellApplication {
  name = "run-project";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    comfy-pkg
    (pkgs.python3.withPackages (ps: [ps.natsort]))
    pkgs.xdg-utils
  ];
  text = ''
    COMFY_HOME="$HOME/.config/comfy-ui"
    WORKFLOWS_DIR="$COMFY_HOME/user/default/workflows"
    PROJECTS="$COMFY_HOME/projects"
    selected="$(find "$PROJECTS" -mindepth 1 -maxdepth 1 -type d |\
        awk -F'/' '{print $NF}' | ${pkgs.fzf}/bin/fzf)"

    PROJECT_DIR="$PROJECTS/$selected"

    NATSORT_PATH=$(python3 -c "import natsort; import os; print(os.path.dirname(natsort.__file__))" | sed 's|/natsort||')
    export PYTHONPATH="$NATSORT_PATH''${PYTHONPATH:+:''$PYTHONPATH}"

    # prepare workflows
    mv "$WORKFLOWS_DIR" "$WORKFLOWS_DIR~"
    ln -s "$PROJECT_DIR/workflows" "$WORKFLOWS_DIR"

    export COMFY_ARGS=(
      "--open"
      "--lowvram"
      "--enable-manager"
      "--output-directory" "$PROJECT_DIR/outputs"
      "$@"
    )

    URL="http://localhost:8188"
    comfy-ui & COMFY_PID=$!

    echo "Waiting for server at $URL"

    until curl --silent --fail "$URL" > /dev/null; do
        if ! kill -0 $COMFY_PID 2>/dev/null; then
            echo "Error: ComfyUI failed to start"
            exit 1
        fi
        sleep 1
    done

    echo "Launching"
    xdg-open "$URL"

    # restore previous workflows
    rm "$WORKFLOWS_DIR"
    mv "$WORKFLOWS_DIR~" "$WORKFLOWS_DIR"

    echo "Closing server"
    kill $COMFY_PID
  '';
}
