import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Background owner for ComfyUI state. The daemon only observes and sends
// commands; it never starts ComfyUI on load.
PluginComponent {
    id: root

    layerNamespacePlugin: "comfyui-manager"

    readonly property string cliPath: (pluginData.cliPath || "comfyui-manager")
    readonly property string comfyHome: (pluginData.comfyHome || "")
    readonly property var configuredRoots: (pluginData.projectRoots || [])
    readonly property int basePort: {
        const value = parseInt(pluginData.basePort || "8188");
        return Number.isFinite(value) && value > 0 ? value : 8188;
    }
    readonly property string extraArgs: (pluginData.extraArgs || "")
    readonly property int pollInterval: {
        const value = parseInt(pluginData.pollInterval || "3000");
        return Number.isFinite(value) && value >= 1000 ? value : 3000;
    }
    readonly property int logLines: {
        const value = parseInt(pluginData.logLines || "200");
        return Number.isFinite(value) && value > 0 ? value : 200;
    }
    readonly property bool stopOnDisable: (pluginData.stopOnDisable === true)

    property var status: ({})
    property var projects: []
    property var roots: []
    property var logs: []
    property string busy: ""
    property string lastError: ""
    property string lastAction: ""
    property string lastActionProjectId: ""
    property string selectedProjectId: (pluginData.lastProjectId || "")
    property bool statusInFlight: false
    property bool actionInFlight: false

    function pluginKey() {
        return root.pluginId || "comfyuiManager";
    }

    function publish(name, value) {
        PluginService.setGlobalVar(pluginKey(), name, value);
    }

    function publishState() {
        publish("status", root.status);
        publish("projects", root.projects);
        publish("roots", root.roots);
        publish("logs", root.logs);
        publish("busy", root.busy);
        publish("lastError", root.lastError);
        publish("selectedProjectId", root.selectedProjectId);
        publish("lastAction", root.lastAction);
    }

    function normalisedRoots() {
        const result = [];
        for (const entry of root.configuredRoots) {
            const value = typeof entry === "string" ? entry : (entry && entry.path ? entry.path : "");
            if (value.trim().length > 0)
                result.push(value.trim());
        }
        return result;
    }

    function baseCommand() {
        const command = ["env"];
        if (root.comfyHome.length > 0)
            command.push("COMFY_HOME=" + root.comfyHome);
        const configured = normalisedRoots();
        if (configured.length > 0)
            command.push("COMFY_PROJECTS=" + configured.join(":"));
        if (root.extraArgs.length > 0)
            command.push("COMFYUI_MANAGER_EXTRA_ARGS=" + root.extraArgs);
        command.push(root.cliPath);
        return command;
    }

    function runCli(args, callback, id, debounce, timeout) {
        Proc.runCommand(
            id || ("comfyuiManager.cli." + Date.now()),
            baseCommand().concat(args),
            callback,
            debounce || 0,
            timeout || 10000
        );
    }

    function parseJson(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function setBusy(value) {
        root.busy = value;
        publish("busy", value);
    }

    function setSelected(projectId) {
        if (!projectId || root.selectedProjectId === projectId)
            return;
        root.selectedProjectId = projectId;
        publish("selectedProjectId", projectId);
        if (root.pluginService && root.pluginId)
            root.pluginService.savePluginData(root.pluginId, "lastProjectId", projectId);
    }

    function setStatus(data) {
        root.status = data || ({});
        if (root.status.phase === "running" && root.status.projectId)
            setSelected(root.status.projectId);
        if (root.status.error)
            root.lastError = root.status.error;
        publish("status", root.status);
        publish("lastError", root.lastError);
    }

    function setProjects(data) {
        root.projects = data.projects || [];
        root.roots = data.projectRoots || [];
        publish("projects", root.projects);
        publish("roots", root.roots);
        const ids = root.projects.map(project => project.id);
        if (root.selectedProjectId && ids.indexOf(root.selectedProjectId) < 0) {
            // Project IDs embed the canonical root. Drop a stale selection so a
            // later start does not send an ID that no longer exists.
            root.selectedProjectId = "";
            publish("selectedProjectId", "");
        }
        if (!root.selectedProjectId) {
            const current = data.currentProjectId || "";
            if (current.length > 0 && ids.indexOf(current) >= 0)
                setSelected(current);
            else if (root.projects.length > 0)
                setSelected(root.projects[0].id);
        }
    }

    function refreshStatus() {
        if (root.statusInFlight)
            return;
        root.statusInFlight = true;
        runCli(["status", "--json"], (stdout, exitCode) => {
            root.statusInFlight = false;
            const data = parseJson(stdout);
            if (data && data.ok !== false)
                setStatus(data);
        }, "comfyuiManager.status");
    }

    function refreshProjects() {
        runCli(["list", "--json"], (stdout, exitCode) => {
            const data = parseJson(stdout);
            if (data && data.ok !== false)
                setProjects(data);
        }, "comfyuiManager.list");
    }

    function refreshLogs() {
        runCli(["logs", "--json", "--lines", String(root.logLines)], (stdout, exitCode) => {
            const data = parseJson(stdout);
            if (data && data.ok !== false) {
                root.logs = data.lines || [];
                publish("logs", root.logs);
            }
        }, "comfyuiManager.logs");
    }

    function commandFailed(stdout, exitCode) {
        const data = parseJson(stdout);
        const message = (data && data.error) ? data.error : ("comfyui-manager failed (exit " + exitCode + ")");
        root.lastError = message;
        publish("lastError", message);
        ToastService.showError("ComfyUI", message);
        refreshStatus();
    }

    function runAction(action, args, projectId) {
        if (root.actionInFlight)
            return;
        root.actionInFlight = true;
        root.lastError = "";
        root.lastAction = action;
        root.lastActionProjectId = projectId || "";
        setBusy(action);
        publish("lastError", "");
        runCli(args, (stdout, exitCode) => {
            root.actionInFlight = false;
            setBusy("");
            const data = parseJson(stdout);
            if (exitCode === 0 && data && data.ok !== false) {
                refreshStatus();
                refreshProjects();
                refreshLogs();
            } else {
                commandFailed(stdout, exitCode);
                refreshProjects();
            }
        }, "comfyuiManager.action", 0, 120000);
    }

    function start(projectId) {
        const id = projectId || PluginService.getGlobalVar(pluginKey(), "selectedProjectId", root.selectedProjectId);
        if (!id) {
            ToastService.showError("ComfyUI", "Select a project first");
            return;
        }
        runAction("start", ["start", "--project-id", id, "--base-port", String(root.basePort), "--json"], id);
    }

    function stop() {
        runAction("stop", ["stop", "--json"], "");
    }

    function restart() {
        runAction("restart", ["restart", "--json"], root.status.projectId || "");
    }

    function switchProject(projectId) {
        const id = projectId || PluginService.getGlobalVar(pluginKey(), "selectedProjectId", root.selectedProjectId);
        if (!id) {
            ToastService.showError("ComfyUI", "Select a project first");
            return;
        }
        runAction("switch", ["switch", "--project-id", id, "--base-port", String(root.basePort), "--json"], id);
    }

    function retry() {
        if (root.lastAction === "switch" && root.lastActionProjectId)
            switchProject(root.lastActionProjectId);
        else if (root.lastAction === "start" && root.lastActionProjectId)
            start(root.lastActionProjectId);
        else if (root.lastAction === "restart")
            restart();
        else {
            refreshStatus();
            refreshProjects();
        }
    }

    function openUi() {
        if (root.actionInFlight)
            return;
        root.actionInFlight = true;
        runCli(["open", "--json"], (stdout, exitCode) => {
            root.actionInFlight = false;
            if (exitCode !== 0)
                commandFailed(stdout, exitCode);
        }, "comfyuiManager.open");
    }

    function refreshAll() {
        refreshStatus();
        refreshProjects();
        refreshLogs();
    }

    function applySettings() {
        refreshProjects();
        refreshStatus();
    }

    onComfyHomeChanged: applySettings()
    onConfiguredRootsChanged: applySettings()
    onPollIntervalChanged: refreshStatus()

    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    IpcHandler {
        target: "comfyuiManager"

        function status(): string {
            return JSON.stringify(root.status);
        }

        function list(): string {
            return JSON.stringify(root.projects);
        }

        function start(projectId: string): string {
            root.start(projectId);
            return "starting";
        }

        function stop(): string {
            root.stop();
            return "stopping";
        }

        function restart(): string {
            root.restart();
            return "restarting";
        }

        function switchProject(projectId: string): string {
            root.switchProject(projectId);
            return "switching";
        }

        function retry(): string {
            root.retry();
            return "retrying";
        }

        function open(): string {
            root.openUi();
            return "opening";
        }

        function refresh(): string {
            root.refreshAll();
            return "refreshing";
        }

        function refreshLogs(): string {
            root.refreshLogs();
            return "loading";
        }
    }

    Component.onCompleted: {
        root.publishState();
        root.refreshProjects();
        root.refreshStatus();
    }

    Component.onDestruction: {
        if (root.stopOnDisable && (root.status.phase === "running" || root.status.phase === "starting")) {
            Quickshell.execDetached(root.baseCommand().concat(["stop"]));
        }
    }
}
