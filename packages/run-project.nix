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
    pkgs.glib
    pkgs.lsof
  ];
  text = ''
    COMFY_HOME="$HOME/.config/comfy-ui"
    WORKFLOWS_DIR="$COMFY_HOME/user/default/workflows"
    PROJECTS="$COMFY_HOME/projects"

    # select project to open
    selected="$(find "$PROJECTS" -mindepth 1 -maxdepth 1 -type d |\
        awk -F'/' '{print $NF}' | ${pkgs.fzf}/bin/fzf)"
    PROJECT_DIR="$PROJECTS/$selected"

    # comfy needs this dependency
    NATSORT_PATH=$(python3 -c "import natsort; import os; print(os.path.dirname(natsort.__file__))" | sed 's|/natsort||')
    export PYTHONPATH="$NATSORT_PATH''${PYTHONPATH:+:''$PYTHONPATH}"

    # look for available port, starting with default
    PORT=8188
    while lsof -Pi :"$PORT" -sTCP:LISTEN -t >/dev/null; do
        PORT=$((PORT+1))
    done

    # prepare workflows
    mv "$WORKFLOWS_DIR" "$WORKFLOWS_DIR~"
    ln -s "$PROJECT_DIR/workflows" "$WORKFLOWS_DIR"

    cleanup() {
        # clear linked workflows and restore old ones
        if [ -e "$WORKFLOWS_DIR~" ]; then
            rm -f "$WORKFLOWS_DIR"
            mv "$WORKFLOWS_DIR~" "$WORKFLOWS_DIR"
        fi
    }

    # run cleanup on exit or ctrl+c
    trap cleanup EXIT INT TERM ERR

    export COMFY_ARGS=(
      "--open"
      "--lowvram"
      "--enable-manager"
      "--output-directory" "$PROJECT_DIR/outputs"
      "--port=$PORT"
      "$@"
    )

    comfy-ui
  '';
}
