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

        if [ -e "$COMFY_HOME/output~" ]; then
            rm -f "$COMFY_HOME/output"
            mv "$COMFY_HOME/output~" "$COMFY_HOME/output"
        fi

        if [ -e "$COMFY_HOME/input~" ]; then
            rm -f "$COMFY_HOME/input"
            mv "$COMFY_HOME/input~" "$COMFY_HOME/input"
        fi
    }

    # run cleanup on exit or ctrl+c
    trap cleanup EXIT INT TERM ERR

    if [ ! -e "$PROJECT_DIR/output" ]; then
        mkdir "$PROJECT_DIR/output"
    fi

    mv "$COMFY_HOME/output" "$COMFY_HOME/output~"
    ln -s "$PROJECT_DIR/output" "$COMFY_HOME"

    mv "$COMFY_HOME/input" "$COMFY_HOME/input~"
    ln -s "$PROJECT_DIR/input" "$COMFY_HOME"

    if [ ! -e "$PROJECT_DIR/input" ]; then
        mkdir "$PROJECT_DIR/input"
    fi

    comfy-ui --open --lowvram --enable-manager --port=$PORT
  '';
}
