import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "comfyui-manager-widget"

    readonly property bool showProjectName: (pluginData.showProjectName !== false)

    PluginGlobalVar {
        id: statusVar
        varName: "status"
        defaultValue: ({})
    }

    PluginGlobalVar {
        id: projectsVar
        varName: "projects"
        defaultValue: []
    }

    PluginGlobalVar {
        id: logsVar
        varName: "logs"
        defaultValue: []
    }

    PluginGlobalVar {
        id: busyVar
        varName: "busy"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: lastErrorVar
        varName: "lastError"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: selectedVar
        varName: "selectedProjectId"
        defaultValue: ""
    }

    property var statusData: (statusVar.value || ({}))
    property var projects: (projectsVar.value || [])
    property var logs: (logsVar.value || [])
    property string busy: (busyVar.value || "")
    property string lastError: (lastErrorVar.value || "")
    property string selectedProjectId: (selectedVar.value || "")

    property string searchText: ""
    property bool showLogs: false
    property string pendingAction: ""
    property string pendingProjectId: ""

    readonly property string phase: (statusData.phase || "stopped")
    readonly property string activeProjectId: (statusData.projectId || "")
    readonly property string activeProjectName: (statusData.project || "")
    readonly property bool isRunning: (phase === "running" || phase === "starting")
    readonly property bool isBusy: (busy.length > 0)
    readonly property var filteredProjects: {
        const query = searchText.trim().toLowerCase();
        if (query.length === 0)
            return projects;
        return projects.filter(project => {
            const name = (project.name || "").toLowerCase();
            const projectRoot = (project.root || "").toLowerCase();
            return name.includes(query) || projectRoot.includes(query);
        });
    }
    readonly property var displayedLogs: {
        if (logs.length > 0)
            return logs;
        return statusData.logTail || [];
    }
    readonly property string detailsText: {
        if (phase === "running")
            return (activeProjectName || "ComfyUI") + " · " + (statusData.url || "");
        if (phase === "starting")
            return "Starting " + (activeProjectName || "ComfyUI") + "…";
        if (phase === "failed")
            return lastError || "Startup failed";
        return "Stopped";
    }
    readonly property string busyText: {
        if (busy === "start")
            return "Starting…";
        if (busy === "stop")
            return "Stopping…";
        if (busy === "restart")
            return "Restarting…";
        if (busy === "switch")
            return "Switching project…";
        return "";
    }

    function callIpc(name, value) {
        const command = ["dms", "ipc", "call", "comfyuiManager", name];
        if (value !== undefined && value !== null && String(value).length > 0)
            command.push(String(value));
        Quickshell.execDetached(command);
    }

    function requestSwitch(projectId) {
        if (!projectId || projectId === activeProjectId)
            return;
        pendingAction = "switch";
        pendingProjectId = projectId;
    }

    function requestRestart() {
        pendingAction = "restart";
        pendingProjectId = "";
    }

    function confirmPending() {
        const action = pendingAction;
        const target = pendingProjectId;
        pendingAction = "";
        pendingProjectId = "";
        if (action === "switch")
            callIpc("switchProject", target);
        else if (action === "restart")
            callIpc("restart");
    }

    function cancelPending() {
        pendingAction = "";
        pendingProjectId = "";
    }

    function statusColor(value) {
        if (value === "running")
            return Theme.primary;
        if (value === "starting")
            return Theme.tertiary;
        if (value === "failed")
            return Theme.error;
        return Theme.surfaceVariantText;
    }

    function projectSubtitle(project) {
        if (!project)
            return "";
        const bits = [project.root || ""];
        if (!project.hasInput || !project.hasOutput || !project.hasWorkflows)
            bits.push("folders will be created");
        return bits.filter(part => part.length > 0).join(" · ");
    }

    function projectName(projectId) {
        const match = projects.find(project => project.id === projectId);
        return match ? match.name : projectId;
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.statusColor(root.phase)
            }

            StyledText {
                text: (root.showProjectName && root.isRunning)
                    ? (root.activeProjectName || "ComfyUI")
                    : "ComfyUI"
                color: Theme.surfaceText
                font.pixelSize: root.textSize
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.statusColor(root.phase)
            }

            StyledText {
                text: "C"
                color: Theme.surfaceText
                font.pixelSize: root.textSize
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    pillRightClickAction: function () {
        root.triggerPopout();
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "ComfyUI"
            detailsText: root.detailsText

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DButton {
                        width: 88
                        height: 36
                        text: root.isRunning ? "Stop" : "Start"
                        enabled: !root.isBusy && root.selectedProjectId.length > 0
                        onClicked: {
                            if (root.isRunning)
                                root.callIpc("stop");
                            else
                                root.callIpc("start", root.selectedProjectId);
                        }
                    }

                    DButton {
                        width: 104
                        height: 36
                        text: "Restart"
                        visible: root.isRunning
                        enabled: !root.isBusy
                        onClicked: root.requestRestart()
                    }

                    DButton {
                        width: 80
                        height: 36
                        text: "Open"
                        visible: root.phase === "running"
                        enabled: !root.isBusy
                        onClicked: root.callIpc("open")
                    }

                    DButton {
                        width: 80
                        height: 36
                        text: root.showLogs ? "Hide logs" : "Logs"
                        onClicked: {
                            root.showLogs = !root.showLogs;
                            if (root.showLogs)
                                root.callIpc("refreshLogs");
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: root.isBusy
                    text: root.busyText
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledRect {
                    width: parent.width
                    visible: root.lastError.length > 0
                    radius: Theme.cornerRadius
                    color: Theme.errorContainer
                    implicitHeight: errorColumn.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: errorColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            width: parent.width
                            text: root.lastError
                            color: Theme.onErrorContainer
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: Theme.spacingS

                            DButton {
                                width: 90
                                height: 32
                                text: "Retry"
                                onClicked: root.callIpc("retry")
                            }

                            DButton {
                                width: 80
                                height: 32
                                text: "Refresh"
                                onClicked: root.callIpc("refresh")
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    visible: root.pendingAction.length > 0
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface
                    implicitHeight: confirmColumn.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: confirmColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            width: parent.width
                            text: root.pendingAction === "switch"
                                ? "Switch to " + root.projectName(root.pendingProjectId) + "?"
                                : "Restart ComfyUI? This only restarts the process."
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: Theme.spacingS

                            DButton {
                                width: 90
                                height: 32
                                text: "Cancel"
                                onClicked: root.cancelPending()
                            }

                            DButton {
                                width: 90
                                height: 32
                                text: "Confirm"
                                onClicked: root.confirmPending()
                            }
                        }
                    }
                }

                DTextField {
                    width: parent.width
                    placeholderText: "Search projects…"
                    text: root.searchText
                    enabled: !root.isBusy
                    onTextChanged: {
                        if (root.searchText !== text)
                            root.searchText = text;
                    }
                }

                Item {
                    width: parent.width
                    height: 216

                    ListView {
                        id: projectList
                        anchors.fill: parent
                        clip: true
                        spacing: Theme.spacingXS
                        model: root.filteredProjects

                        delegate: StyledRect {
                            required property var modelData

                            width: ListView.view ? ListView.view.width : 0
                            height: 50
                            radius: Theme.cornerRadius
                            color: (modelData.id === root.selectedProjectId)
                                ? Theme.selectedContainer
                                : (projectMouse.containsMouse ? Theme.surfaceHover : "transparent")

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                color: (modelData.id === root.activeProjectId)
                                    ? root.statusColor(root.phase)
                                    : "transparent"
                                border.width: (modelData.id === root.activeProjectId) ? 0 : 1
                                border.color: Theme.surfaceVariantText
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM + 16
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXXS

                                StyledText {
                                    width: parent.width
                                    text: modelData.name || ""
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: (modelData.id === root.selectedProjectId)
                                        ? Theme.fontWeightMedium
                                        : Theme.fontWeight
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.projectSubtitle(modelData)
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeXSmall
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: projectMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.isBusy
                                onClicked: selectedVar.set(modelData.id)
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.filteredProjects.length === 0
                        text: root.projects.length === 0 ? "No projects found" : "No matches"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                DButton {
                    width: parent.width
                    height: 40
                    enabled: !root.isBusy && root.selectedProjectId.length > 0
                    text: {
                        if (root.isRunning) {
                            if (root.selectedProjectId === root.activeProjectId)
                                return "Current project is running";
                            return "Switch to selected project";
                        }
                        if (root.phase === "failed")
                            return "Start selected project";
                        return "Start selected project";
                    }
                    onClicked: {
                        if (root.isRunning) {
                            if (root.selectedProjectId !== root.activeProjectId)
                                root.requestSwitch(root.selectedProjectId);
                        } else {
                            root.callIpc("start", root.selectedProjectId);
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    visible: root.showLogs
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface
                    implicitHeight: 188

                    ListView {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        clip: true
                        model: root.displayedLogs

                        delegate: StyledText {
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            text: modelData
                            color: Theme.surfaceVariantText
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeXSmall
                            wrapMode: Text.WrapAnywhere
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.displayedLogs.length === 0
                        text: "No logs"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }

    popoutWidth: 440
    popoutHeight: root.showLogs ? 700 : 560
}
