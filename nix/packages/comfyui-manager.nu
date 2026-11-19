#!/usr/bin/env nu

# comfyui-manager
#
# Run ComfyUI against a project directory, or create a new project.
#
# Projects live in $COMFY_HOME/projects (default: ~/.config/comfy-ui/projects)
# and are selected interactively with fzf. Each project's workflows, input and
# output directories are swapped into place for the duration of the run and
# restored afterwards.

def comfy-home [] {
    (
        $env.COMFY_HOME?
        | default ($env.HOME | path join ".config" "comfy-ui")
        | path expand
    )
}

def projects-dir [] {
    comfy-home | path join "projects"
}

def path-kind [path: path] {
    $path | path type
}

# Move `target` (if it exists) aside, then point it at `source`.
# Returns whether `target` existed before the swap, so it can be restored.
def swap-link [target: path, source: path] {
    let backup = $"($target)~"

    # Recover from a previous run that was interrupted before cleanup.
    if (path-kind $backup) != null {
        if (path-kind $target) == null or (path-kind $target) == "symlink" {
            rm -f -- $target
            ^mv -- $backup $target
        } else {
            error make {
                msg: $"Refusing to replace ($target): both it and its backup ($backup) exist."
            }
        }
    }

    let had_target = (path-kind $target) != null
    if $had_target {
        ^mv -- $target $backup
    }

    ^mkdir -p -- ($target | path dirname)
    ^ln -sfn -- $source $target
    $had_target
}

# Undo a swap-link performed by this process.
def restore-link [target: path, had_target: bool] {
    let backup = $"($target)~"
    if (path-kind $backup) != null {
        rm -f -- $target
        ^mv -- $backup $target
    } else if not $had_target and (path-kind $target) == "symlink" {
        # The target did not exist before this run; remove the link we added.
        rm -f -- $target
    }
}

def select-project [] {
    let projects = (projects-dir)
    if not ($projects | path exists) {
        error make {
            msg: $"Projects directory does not exist: ($projects). Run `comfyui-manager create` first."
        }
    }

    let candidates = (
        ^find -H $projects -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
        | lines
        | where { |line| $line != "" }
        | sort
    )
    if ($candidates | is-empty) {
        error make {
            msg: $"No projects found in ($projects). Run `comfyui-manager create` first."
        }
    }

    let selected = (
        $candidates
        | str join "\n"
        | ^fzf --select-1 --exit-0 --prompt "ComfyUI project> "
        | str trim
    )
    if ($selected | is-empty) {
        error make { msg: "No project selected." }
    }
    $selected
}

def free-port [start: int] {
    mut port = $start
    loop {
        let result = (^lsof -Pi $":($port)" -sTCP:LISTEN -t | complete)
        if ($result.exit_code != 0) or (($result.stdout | str trim) | is-empty) {
            break
        }
        $port += 1
    }
    $port
}

def natsort-site-packages [] {
    ^python3 -c "import natsort, os; print(os.path.dirname(os.path.dirname(natsort.__file__)))"
    | str trim
}

def run-comfy [port: int] {
    # comfy-ui reads these to find its writable base directory, and ComfyUI
    # needs natsort on PYTHONPATH.
    $env.COMFY_USER_DIR = (comfy-home)
    let natsort = (natsort-site-packages)
    let existing = ($env.PYTHONPATH? | default "")
    $env.PYTHONPATH = if ($existing | is-empty) {
        $natsort
    } else {
        $"($natsort):($existing)"
    }

    try {
        ^comfy-ui --lowvram --enable-manager $"--port=($port)"
        0
    } catch { |err|
        if not ($err.msg | str contains "terminated by a signal") {
            print --stderr $"comfyui-manager: ($err.msg)"
        }
        let code = ($env.LAST_EXIT_CODE? | default 1)
        if $code == 0 { 1 } else { $code }
    }
}

def run-project [] {
    let comfy_home = (comfy-home)
    let workflows_dir = ($comfy_home | path join "user" "default" "workflows")
    let project = (select-project)
    let project_dir = ((projects-dir) | path join $project)
    let project_workflows = ($project_dir | path join "workflows")
    let project_output = ($project_dir | path join "output")
    let project_input = ($project_dir | path join "input")

    ^mkdir -p -- $project_output $project_input
    ^mkdir -p -- ($workflows_dir | path dirname)
    ^mkdir -p -- $comfy_home

    let port = (free-port 8188)

    # Swap directories one at a time so a failure part-way through still
    # restores everything that was already swapped.
    let had_workflows = (swap-link $workflows_dir $project_workflows)
    let status = (
        try {
            let had_output = (swap-link ($comfy_home | path join "output") $project_output)
            try {
                let had_input = (swap-link ($comfy_home | path join "input") $project_input)
                try {
                    run-comfy $port
                } finally {
                    restore-link ($comfy_home | path join "input") $had_input
                }
            } finally {
                restore-link ($comfy_home | path join "output") $had_output
            }
        } finally {
            restore-link $workflows_dir $had_workflows
        }
    )

    exit $status
}

# Create a new ComfyUI project in the current directory.
def "main create" [] {
    print $"Initializing ComfyUI project in ((pwd))..."
}

# Run ComfyUI with one of the projects in $COMFY_HOME/projects.
def "main run" [] {
    run-project
}

def main [] {
    run-project
}
