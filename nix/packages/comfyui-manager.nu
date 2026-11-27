#!/usr/bin/env nu

# comfyui-manager
#
# Run ComfyUI against a project directory, or create a new project.
#
# Projects live in $COMFY_HOME/projects (default: ~/.config/comfy-ui/projects).
# The interactive `run` command selects a project with fzf and runs ComfyUI in
# the foreground. `start`/`stop`/`restart`/`switch` manage a background instance
# through a transient systemd user unit, so it survives shell restarts.
#
# Every project's workflows, input and output directories are exposed to
# ComfyUI for the duration of the run. Input/output use ComfyUI's directory
# flags; workflows are swapped via a symlink and restored afterwards.

# ---------------------------------------------------------------------------
# Paths and environment
# ---------------------------------------------------------------------------

def comfy-home [] {
    let configured = ($env.COMFY_HOME? | default "")
    let home = if ($configured | is-empty) {
        $env.HOME | path join ".config" "comfy-ui"
    } else {
        $configured
    }
    $home | path expand
}

def projects-dir [] {
    ((comfy-home) | path join "projects") | path expand
}

# Project roots come from COMFY_PROJECTS as a colon-separated list. An empty
# value keeps the historical single root under COMFY_HOME.
def project-roots [] {
    let configured = ($env.COMFY_PROJECTS? | default "")
    let roots = if ($configured | is-empty) {
        [ (projects-dir) ]
    } else {
        $configured
        | split row ":"
        | where { |entry| $entry != "" }
        | each { |entry| $entry | path expand }
    }
    $roots | uniq
}

def state-base [] {
    let configured = ($env.XDG_STATE_HOME? | default "")
    if ($configured | is-empty) {
        $env.HOME | path join ".local" "state"
    } else {
        $configured
    }
}

def state-dir [] {
    (state-base) | path join "comfyui-manager"
}

def state-file [] {
    (state-dir) | path join "state.json"
}

def lock-dir [] {
    (state-dir) | path join "manager.lock"
}

def unit-name [] {
    "comfyui-manager.service"
}

def manager-bin [] {
    let override = ($env.COMFYUI_MANAGER_BIN? | default "")
    if not ($override | is-empty) {
        $override | path expand
    } else {
        # Prefer the installed wrapper. It supplies the runtime PATH (comfyui,
        # lsof, and friends) to the systemd unit. Nu's `which`
        # reports the executing .nu script as a custom command, so query the
        # shell PATH instead.
        let found = (^sh -c "command -v comfyui-manager" | complete)
        if ($found.exit_code == 0) and (not (($found.stdout | str trim) | is-empty)) {
            $found.stdout | str trim | path expand
        } else {
            let current = ($env.CURRENT_FILE? | default "")
            if not ($current | is-empty) {
                $current | path expand
            } else {
                "comfyui-manager"
            }
        }
    }
}

def now [] {
    date now | format date "%Y-%m-%dT%H:%M:%S%z"
}

def epoch-now [] {
    date now | format date "%s" | into int
}

def path-kind [path] {
    if ($path | path exists) {
        $path | path type
    } else {
        null
    }
}

def link-target [path] {
    if (path-kind $path) == "symlink" {
        ^readlink -- $path | str trim
    } else {
        null
    }
}

# ---------------------------------------------------------------------------
# State and locking
# ---------------------------------------------------------------------------

def read-state [] {
    let file = (state-file)
    if ($file | path exists) {
        try {
            open $file
        } catch {
            {}
        }
    } else {
        {}
    }
}

def write-state [state: record] {
    ^mkdir -p -- (state-dir)
    let file = (state-file)
    let tmp = $"($file).tmp"
    $state | to json | save -f $tmp
    ^mv -f -- $tmp $file
}

def update-state [patch: record] {
    let current = (read-state)
    write-state ($current | merge $patch)
}

def acquire-lock [] {
    ^mkdir -p -- (state-dir)
    let dir = (lock-dir)
    if ($dir | path exists) {
        let pid = (try {
            open ($dir | path join "pid") | str trim | into int
        } catch {
            0
        })
        let alive = if $pid > 0 {
            ((^kill -0 $pid | complete).exit_code) == 0
        } else {
            false
        }
        if $alive {
            error make {
                msg: "another comfyui-manager operation is in progress"
            }
        }
        rm -rf -- $dir
    }
    ^mkdir -- $dir
    ($nu.pid | into string) | save -f ($dir | path join "pid")
}

def release-lock [] {
    let dir = (lock-dir)
    if ($dir | path exists) {
        rm -rf -- $dir
    }
}

# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------

def project-info [root: string, name: string] {
    let path = ($root | path join $name)
    {
        id: $"($root)::($name)",
        name: $name,
        root: $root,
        path: ($path | into string),
        hasInput: ((($path | path join "input") | path exists)),
        hasOutput: ((($path | path join "output") | path exists)),
        hasWorkflows: ((($path | path join "workflows") | path exists))
    }
}

def project-entries [] {
    project-roots | each { |root|
        let dir = ($root | into string)
        if not ($dir | path exists) {
            []
        } else {
            ^find -H $dir -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
            | lines
            | where { |line| $line != "" and not ($line | str starts-with ".") }
            | sort
            | each { |name| project-info $dir $name }
        }
    } | flatten
}

def resolve-project [name: string] {
    if ($name | is-empty) {
        error make { msg: "project name is required" }
    }
    if ($name | str contains "/") or ($name == ".") or ($name == "..") {
        error make { msg: $"invalid project name: ($name)" }
    }
    let matches = (project-entries | where { |entry| $entry.name == $name })
    if ($matches | is-empty) {
        error make { msg: $"unknown project: ($name)" }
    }
    if ($matches | length) > 1 {
        let ids = ($matches | get id | str join ", ")
        error make {
            msg: $"project name '($name)' is ambiguous; use one of: ($ids)"
        }
    }
    $matches | get 0
}

def normalize-project-id [id: string] {
    let parts = ($id | split row "::")
    if (($parts | length) < 2) {
        $id
    } else {
        let root = (($parts | first) | path expand | into string)
        let name = ($parts | skip 1 | str join "::")
        $"($root)::($name)"
    }
}

def resolve-project-id [id: string] {
    if ($id | is-empty) {
        error make { msg: "project id is required" }
    }
    let normalized = (normalize-project-id $id)
    let matches = (project-entries | where { |entry| $entry.id == $normalized })
    if ($matches | is-empty) {
        error make { msg: $"unknown project id: ($id)" }
    }
    $matches | get 0
}

def resolve-selection [project: any, project_id: any] {
    let has_name = not (($project | default "") | is-empty)
    let has_id = not (($project_id | default "") | is-empty)
    if $has_name and $has_id {
        error make { msg: "use either --project or --project-id, not both" }
    }
    if not $has_name and not $has_id {
        error make { msg: "one of --project or --project-id is required" }
    }
    if $has_id {
        resolve-project-id $project_id
    } else {
        resolve-project $project
    }
}

def project-label [entry: record] {
    $"($entry.name) — ($entry.root)"
}

def select-project [] {
    let entries = (project-entries)
    if ($entries | is-empty) {
        error make {
            msg: $"No projects found in (project-roots | str join ':'). Run `comfyui-manager create` first."
        }
    }
    let choices = ($entries | each { |entry|
        {
            label: (project-label $entry),
            entry: $entry
        }
    })
    let selected = (
        $choices
        | get label
        | str join "\n"
        | ^fzf --select-1 --exit-0 --prompt "ComfyUI project> "
        | str trim
    )
    if ($selected | is-empty) {
        error make { msg: "No project selected." }
    }
    let match = ($choices | where { |choice| $choice.label == $selected })
    if ($match | is-empty) {
        error make { msg: "No project selected." }
    }
    $match | get 0 | get entry
}

# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------

def port-busy [port: int] {
    let result = (^lsof -Pi $":($port)" -sTCP:LISTEN -t | complete)
    ($result.exit_code == 0) and (not (($result.stdout | str trim) | is-empty))
}

def free-port [start: int] {
    mut port = $start
    loop {
        if not (port-busy $port) {
            break
        }
        $port += 1
    }
    $port
}

# ---------------------------------------------------------------------------
# Workflow symlink swap
# ---------------------------------------------------------------------------

def swap-workflow [target: string, source: string] {
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
    {
        target: ($target | into string),
        backup: ($backup | into string),
        source: ($source | into string),
        hadTarget: $had_target
    }
}

def restore-workflow [swap] {
    if $swap == null {
        return
    }

    let target = ($swap.target | into string)
    let backup = ($swap.backup | into string)

    if (path-kind $backup) != null {
        if (path-kind $target) == null or (path-kind $target) == "symlink" {
            rm -f -- $target
            ^mv -- $backup $target
        } else {
            print --stderr $"comfyui-manager: not restoring ($target); it is no longer a symlink"
        }
    } else if ($swap.hadTarget == false) and ((link-target $target) == ($swap.source | into string)) {
        rm -f -- $target
    }
}

# Restore a legacy `target~` backup if the current target is missing or still a
# symlink. This repairs leftovers from older versions that swapped input/output.
def restore-backup-only [target: string] {
    let backup = $"($target)~"
    if (path-kind $backup) != null and ((path-kind $target) == null or (path-kind $target) == "symlink") {
        rm -f -- $target
        ^mv -- $backup $target
        true
    } else {
        false
    }
}

# ---------------------------------------------------------------------------
# systemd unit helpers
# ---------------------------------------------------------------------------

def unit-active [] {
    ((^systemctl --user is-active --quiet (unit-name) | complete).exit_code) == 0
}

def unit-failed [] {
    ((^systemctl --user is-failed --quiet (unit-name) | complete).exit_code) == 0
}

def unit-property [property: string] {
    let result = (^systemctl --user show (unit-name) -p $property --value | complete)
    if $result.exit_code == 0 {
        $result.stdout | str trim
    } else {
        ""
    }
}

def unit-pid [] {
    let value = (unit-property "MainPID")
    if ($value | is-empty) {
        0
    } else {
        try {
            $value | into int
        } catch {
            0
        }
    }
}

def unit-sub-state [] {
    unit-property "SubState"
}

def health-ok [] {
    let port = ((read-state) | get -o port)
    if $port == null {
        false
    } else {
        let url = $"http://127.0.0.1:($port)/system_stats"
        ((^curl -fsS --max-time 1 -o /dev/null $url | complete).exit_code) == 0
    }
}

def log-text [line_count: int] {
    let result = (^journalctl --user -u (unit-name) -n $line_count --no-pager -o cat | complete)
    $result.stdout
}

def log-lines [line_count: int] {
    (log-text $line_count) | lines | where { |line| $line != "" }
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def json-out [value] {
    print ($value | to json -r)
}

def fail-json [message: string, as_json: bool] {
    if $as_json {
        json-out { ok: false, error: $message }
    } else {
        print --stderr $"comfyui-manager: ($message)"
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Process helpers
# ---------------------------------------------------------------------------

def run-comfy [port: int, input: string, output: string] {
    # nixpkgs' comfyui wrapper unsets PYTHONPATH; all Python dependencies are
    # part of its wrapped environment. The base directory and database are
    # pinned explicitly so state stays under COMFY_HOME.
    let home = (comfy-home)

    let extra = (($env.COMFYUI_MANAGER_EXTRA_ARGS? | default "") | split row " " | where { |arg| $arg != "" })
    let fake_command = ($env.COMFYUI_MANAGER_COMFY_CMD? | default "")

    try {
        if not ($fake_command | is-empty) {
            # Test hook: exercise the lifecycle without starting ComfyUI.
            ^sh -c $fake_command
        } else {
            ^comfyui --lowvram --enable-manager --disable-auto-launch $"--base-directory=($home)" $"--database-url=sqlite:///($home)/user/comfyui.db" $"--port=($port)" $"--input-directory=($input)" $"--output-directory=($output)" ...$extra
        }
        ($env.LAST_EXIT_CODE? | default 0)
    } catch { |err|
        if not ($err.msg | str contains "terminated by a signal") {
            print --stderr $"comfyui-manager: ($err.msg)"
        }
        let code = ($env.LAST_EXIT_CODE? | default 1)
        if $code == 0 { 1 } else { $code }
    }
}

def run-with-project [project: record, port: int, --stateful] {
    let home = (comfy-home)
    let project_dir = ($project.path | into string)
    let workflows_dir = ($home | path join "user" "default" "workflows")
    let project_workflows = ($project_dir | path join "workflows")
    let project_input = ($project_dir | path join "input")
    let project_output = ($project_dir | path join "output")

    ^mkdir -p -- $project_input $project_output $project_workflows
    ^mkdir -p -- ($workflows_dir | path dirname)

    let swap = (swap-workflow ($workflows_dir | into string) ($project_workflows | into string))
    if $stateful {
        let started = (now)
        update-state {
            phase: "running",
            swap: $swap,
            project: $project.name,
            projectId: $project.id,
            projectRoot: $project.root,
            port: $port,
            startedAt: $started,
            updatedAt: $started
        }
    }

    let code = (
        try {
            run-comfy $port ($project_input | into string) ($project_output | into string)
        } catch { |err|
            print --stderr $"comfyui-manager: ($err.msg)"
            let exit_code = ($env.LAST_EXIT_CODE? | default 1)
            if $exit_code == 0 { 1 } else { $exit_code }
        }
    )

    restore-workflow $swap

    if $stateful {
        let phase = if $code == 0 { "stopped" } else { "failed" }
        update-state {
            phase: $phase,
            swap: null,
            exitCode: $code,
            updatedAt: (now),
            error: (if $code == 0 { null } else { $"comfyui exited with code ($code)" })
        }
    }

    $code
}

# ---------------------------------------------------------------------------
# Control operations (no output formatting, no locking)
# ---------------------------------------------------------------------------

def cleanup-state [] {
    let current = (read-state)
    let swap = ($current | get -o swap)
    if $swap != null {
        restore-workflow $swap
    }
    if (($current | get -o phase) == "failed") {
        update-state { swap: null }
    } else {
        update-state { phase: "stopped", swap: null }
    }
}

def do-start [project: record, port: any, base_port: int] {
    if (unit-active) {
        let current = (read-state)
        let current_id = ($current | get -o projectId)
        let current_project = ($current | get -o project)
        let same_project = ($current_id == $project.id) or (($current_id == null) and ($current_project == $project.name))
        if $same_project {
            let current_port = ($current | get -o port)
            let current_phase = if (health-ok) { "running" } else { "starting" }
            return {
                ok: true,
                phase: $current_phase,
                project: $project.name,
                projectId: $project.id,
                projectRoot: $project.root,
                port: $current_port,
                url: (if $current_port == null { null } else { $"http://127.0.0.1:($current_port)/" }),
                alreadyRunning: true
            }
        }
        error make {
            msg: $"ComfyUI is already running project '($current_project)'. Use `comfyui-manager switch --project-id ($project.id)`."
        }
    }

    cleanup-state

    let chosen_port = if $port == null { free-port $base_port } else { $port }
    if (($port != null) and (port-busy $chosen_port)) {
        error make { msg: $"port ($chosen_port) is already in use" }
    }

    let home = (comfy-home)
    let project_roots = (project-roots | str join ":")
    let state_base_dir = (state-base)
    let started = (now)
    write-state {
        phase: "starting",
        project: $project.name,
        projectId: $project.id,
        projectRoot: $project.root,
        port: $chosen_port,
        basePort: $base_port,
        url: $"http://127.0.0.1:($chosen_port)/",
        home: $home,
        projectRoots: (project-roots),
        startedAt: $started,
        startedEpoch: (epoch-now),
        updatedAt: $started,
        unit: (unit-name),
        error: null,
        exitCode: null,
        swap: null
    }

    let self = (manager-bin)
    mut args = [
        "--user"
        $"--unit=(unit-name)"
        "--collect"
        "--property=TimeoutStopSec=20"
        "--property=Restart=no"
        $"--property=ExecStopPost=($self) _cleanup"
        $"--setenv=HOME=($env.HOME)"
        $"--setenv=XDG_STATE_HOME=($state_base_dir)"
        $"--setenv=COMFY_HOME=($home)"
        $"--setenv=COMFY_PROJECTS=($project_roots)"
    ]

    let extra = ($env.COMFYUI_MANAGER_EXTRA_ARGS? | default "")
    if not ($extra | is-empty) {
        $args = ($args | append $"--setenv=COMFYUI_MANAGER_EXTRA_ARGS=($extra)")
    }
    let fake_command = ($env.COMFYUI_MANAGER_COMFY_CMD? | default "")
    if not ($fake_command | is-empty) {
        $args = ($args | append $"--setenv=COMFYUI_MANAGER_COMFY_CMD=($fake_command)")
    }
    $args = ($args ++ [$self "_run" "--project-id" $project.id "--port" ($chosen_port | into string)])

    let result = (^systemd-run ...$args | complete)
    if $result.exit_code != 0 {
        let message = if (($result.stderr | str trim) | is-empty) {
            "failed to start the systemd unit"
        } else {
            $result.stderr | str trim
        }
        update-state { phase: "failed", error: $message, updatedAt: (now) }
        error make { msg: $message }
    }

    # systemd-run returns before the unit has necessarily entered the active
    # state. Give it a short window so an immediate ExecStart failure is
    # reported instead of looking like a long startup.
    mut active = (unit-active)
    mut tries = 0
    loop {
        if $active or $tries >= 8 {
            break
        }
        sleep 250ms
        $active = (unit-active)
        $tries += 1
    }
    if not $active {
        let tail = (log-lines 20)
        let message = if ($tail | is-empty) {
            "ComfyUI failed to start"
        } else {
            $tail | last
        }
        update-state { phase: "failed", error: $message, updatedAt: (now) }
        error make { msg: $message }
    }

    {
        ok: true,
        phase: "starting",
        project: $project.name,
        projectId: $project.id,
        projectRoot: $project.root,
        port: $chosen_port,
        url: $"http://127.0.0.1:($chosen_port)/",
        unit: (unit-name)
    }
}

def do-stop [] {
    let current = (read-state)
    let project = ($current | get -o project)
    let port = ($current | get -o port)

    if (unit-active) {
        let result = (^systemctl --user stop (unit-name) | complete)
        if $result.exit_code != 0 {
            let message = if (($result.stderr | str trim) | is-empty) {
                "failed to stop the systemd unit"
            } else {
                $result.stderr | str trim
            }
            error make { msg: $message }
        }
    }

    cleanup-state
    update-state {
        phase: "stopped",
        swap: null,
        error: null,
        exitCode: 0,
        updatedAt: (now)
    }

    {
        ok: true,
        phase: "stopped",
        project: $project,
        projectId: ($current | get -o projectId),
        projectRoot: ($current | get -o projectRoot),
        port: $port
    }
}

def do-status [] {
    let current = (read-state)
    let active = (unit-active)
    let failed = (unit-failed)
    let recorded_phase = ($current | get -o phase)
    let recorded_epoch = ($current | get -o startedEpoch)
    let stale_start = if ($recorded_phase == "starting") and (not $active) {
        if $recorded_epoch == null {
            true
        } else {
            ((epoch-now) - $recorded_epoch) > 30
        }
    } else {
        false
    }
    let phase = if $active {
        if (health-ok) { "running" } else { "starting" }
    } else if $failed or ($recorded_phase == "failed") or ($recorded_phase == "running") or $stale_start {
        "failed"
    } else if ($recorded_phase == "starting") {
        "starting"
    } else {
        "stopped"
    }

    let port = ($current | get -o port)
    let project = ($current | get -o project)
    let pid = (unit-pid)
    let recorded_error = ($current | get -o error)
    let error = if ($phase == "failed") and ($recorded_error == null) {
        if $stale_start { "ComfyUI startup did not finish" } else { "ComfyUI exited unexpectedly" }
    } else {
        $recorded_error
    }

    {
        ok: true,
        phase: $phase,
        running: ($phase == "running"),
        ready: ($phase == "running"),
        project: $project,
        projectId: ($current | get -o projectId),
        projectRoot: ($current | get -o projectRoot),
        port: $port,
        url: (if $port == null { null } else { $"http://127.0.0.1:($port)/" }),
        pid: (if $pid > 0 { $pid } else { null }),
        unit: (unit-name),
        unitActive: $active,
        unitSubState: (unit-sub-state),
        startedAt: ($current | get -o startedAt),
        error: $error,
        exitCode: ($current | get -o exitCode),
        home: (comfy-home),
        projectRoots: (project-roots),
        projectsDir: (project-roots | get 0),
        logTail: (if $phase == "failed" { log-lines 20 } else { [] })
    }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

# Create a new ComfyUI project in the current directory.
def "main create" [] {
    print $"Initializing ComfyUI project in ((pwd))..."
}

# List projects as JSON or plain text.
def "main list" [--home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        let state = (read-state)
        let current_id = ($state | get -o projectId)
        let current_name = ($state | get -o project)
        let entries = (project-entries)
        let current_name_count = if $current_name == null { 0 } else {
            $entries | where { |entry| $entry.name == $current_name } | length
        }
        let projects = (
            $entries
            | each { |entry|
                let is_current = if $current_id != null {
                    $entry.id == $current_id
                } else {
                    ($current_name_count == 1) and ($entry.name == $current_name)
                }
                $entry | merge { isCurrent: $is_current }
            }
        )
        let roots = (
            project-roots
            | each { |root| { path: ($root | into string), exists: ($root | path exists) } }
        )
        let result = {
            ok: true,
            home: (comfy-home),
            projectRoots: $roots,
            projectsDir: (project-roots | get 0),
            currentProject: $current_name,
            currentProjectId: $current_id,
            projects: $projects
        }
        if $json {
            json-out $result
        } else {
            for project in $projects {
                let marker = if $project.isCurrent { "*" } else { " " }
                let label = (project-label $project)
                print $"($marker) ($label)"
            }
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Show the current phase and probe the running instance.
def "main status" [--home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        let result = (do-status)
        if $json {
            json-out $result
        } else {
            print $"phase: ($result.phase)"
            if $result.project != null {
                print $"project: ($result.project)"
            }
            if $result.url != null {
                print $"url: ($result.url)"
            }
            if $result.error != null {
                print $"error: ($result.error)"
            }
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Start ComfyUI with a project in the background.
def "main start" [--project: string, --project-id: string, --port: int, --base-port: int = 8188, --home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        let selected = (resolve-selection $project $project_id)
        acquire-lock
        try {
            let result = (do-start $selected $port $base_port)
            if $json {
                json-out $result
            } else if ($result | get -o alreadyRunning) == true {
                print $"ComfyUI is already running project ($result.project)"
            } else {
                print $"Starting ($result.project) on ($result.url)"
            }
        } finally {
            release-lock
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Stop the running ComfyUI instance and restore the project links.
def "main stop" [--json] {
    try {
        acquire-lock
        try {
            let result = (do-stop)
            if $json {
                json-out $result
            } else if $result.project != null {
                print $"Stopped ($result.project)"
            } else {
                print "ComfyUI is stopped"
            }
        } finally {
            release-lock
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Restart the currently selected project.
def "main restart" [--home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        acquire-lock
        try {
            let current = (read-state)
            let project_id = ($current | get -o projectId)
            let project_name = ($current | get -o project)
            if $project_id == null and $project_name == null {
                error make { msg: "no project has been started yet" }
            }
            let selected = if $project_id != null {
                resolve-project-id $project_id
            } else {
                resolve-project $project_name
            }
            let port = ($current | get -o port)
            let base_port_value = ($current | get -o basePort)
            let base_port = if $base_port_value == null { 8188 } else { $base_port_value }
            let _stopped = (do-stop)
            let result = (do-start $selected $port $base_port)
            if $json {
                json-out ($result | merge { previousProject: $selected.name })
            } else {
                print $"Restarted ($result.project) on ($result.url)"
            }
        } finally {
            release-lock
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Stop the current project, then start the selected one.
def "main switch" [--project: string, --project-id: string, --base-port: int = 8188, --home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        let selected = (resolve-selection $project $project_id)
        acquire-lock
        try {
            let previous = ((read-state) | get -o project)
            let _stopped = (do-stop)
            let result = (do-start $selected null $base_port)
            if $json {
                json-out ($result | merge { previousProject: $previous })
            } else {
                print $"Switched to ($result.project) on ($result.url)"
            }
        } finally {
            release-lock
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Show recent unit logs.
def "main logs" [--lines: int = 100, --json] {
    try {
        let text = (log-text $lines)
        if $json {
            json-out { ok: true, lines: ($text | lines) }
        } else {
            print $text
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Open the running ComfyUI UI in the default browser.
def "main open" [--json] {
    try {
        if not (unit-active) {
            error make { msg: "ComfyUI is not running" }
        }
        let port = ((read-state) | get -o port)
        if $port == null {
            error make { msg: "no port is recorded for the running instance" }
        }
        let url = $"http://127.0.0.1:($port)/"
        let result = (^xdg-open $url | complete)
        if $result.exit_code != 0 {
            error make { msg: ($result.stderr | str trim) }
        }
        if $json {
            json-out { ok: true, url: $url }
        } else {
            print $"Opened ($url)"
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Recover an interrupted run and restore legacy input/output backups.
def "main repair" [--home: path, --json] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    try {
        if (unit-active) {
            error make { msg: "stop ComfyUI before repairing links" }
        }
        acquire-lock
        try {
            let current = (read-state)
            let swap = ($current | get -o swap)
            if $swap != null {
                restore-workflow $swap
            }

            let targets = [
                ((comfy-home) | path join "user" "default" "workflows" | into string)
                ((comfy-home) | path join "input" | into string)
                ((comfy-home) | path join "output" | into string)
            ]
            let restored = (
                $targets
                | each { |target| if (restore-backup-only $target) { $target } else { null } }
                | where { |target| $target != null }
            )

            let phase = if (($current | get -o phase) == "failed") { "failed" } else { "stopped" }
            update-state { swap: null, phase: $phase, updatedAt: (now) }
            let result = { ok: true, restored: $restored, phase: $phase }
            if $json {
                json-out $result
            } else {
                print $"Restored ($restored | length) backup(s)"
            }
        } finally {
            release-lock
        }
    } catch { |err|
        fail-json $err.msg $json
    }
}

# Run ComfyUI with one of the projects in the foreground.
def "main run" [--project: string, --project-id: string, --port: int, --base-port: int = 8188, --home: path] {
    if $home != null {
        $env.COMFY_HOME = $home
    }
    if (unit-active) {
        error make { msg: "ComfyUI is already running in the background; stop it first" }
    }
    let has_name = not (($project | default "") | is-empty)
    let has_id = not (($project_id | default "") | is-empty)
    let selected = if not $has_name and not $has_id {
        select-project
    } else {
        resolve-selection $project $project_id
    }
    let chosen_port = if $port == null { free-port $base_port } else { $port }
    if (($port != null) and (port-busy $chosen_port)) {
        error make { msg: $"port ($chosen_port) is already in use" }
    }
    let code = (run-with-project $selected $chosen_port)
    exit $code
}

# Internal entrypoint used by the systemd unit.
def "main _run" [--project-id: string, --port: int] {
    try {
        if ($project_id | is-empty) or ($port == null) {
            error make { msg: "_run requires --project-id and --port" }
        }
        let project = (resolve-project-id $project_id)
        let code = (run-with-project $project $port --stateful)
        exit $code
    } catch { |err|
        update-state { phase: "failed", error: $err.msg, updatedAt: (now) }
        print --stderr $"comfyui-manager: ($err.msg)"
        exit 1
    }
}

# Internal cleanup hook, also used by systemd's ExecStopPost.
def "main _cleanup" [] {
    try {
        cleanup-state
        update-state { updatedAt: (now) }
    } catch { |err|
        print --stderr $"comfyui-manager cleanup: ($err.msg)"
        exit 1
    }
}

def main [] {
    if (unit-active) {
        error make { msg: "ComfyUI is already running in the background; use `comfyui-manager stop` first" }
    }
    let selected = (select-project)
    let port = (free-port 8188)
    let code = (run-with-project $selected $port)
    exit $code
}
