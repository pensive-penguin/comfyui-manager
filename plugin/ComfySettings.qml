import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "comfyuiManager"

    StyledText {
        width: parent.width
        text: "ComfyUI"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Starts one ComfyUI project at a time as a transient systemd user unit. Nothing starts automatically."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "cliPath"
        label: "CLI path"
        description: "The comfyui-manager executable used by the plugin daemon."
        placeholder: "comfyui-manager"
        defaultValue: "comfyui-manager"
    }

    StringSetting {
        settingKey: "comfyHome"
        label: "ComfyUI home"
        description: "Overrides COMFY_HOME. Leave empty to use the CLI default."
        placeholder: "~/.config/comfy-ui"
        defaultValue: ""
    }

    ListSettingWithInput {
        settingKey: "projectRoots"
        label: "Project roots"
        description: "Additional project directories. Leave empty to use $COMFY_HOME/projects. Names may repeat across roots; the widget uses the full path to distinguish them."
        defaultValue: []
        fields: [
            {
                id: "path",
                label: "Path",
                placeholder: "/mnt/data/Data/comfy-projects",
                width: 360
            }
        ]
    }

    StringSetting {
        settingKey: "basePort"
        label: "Base port"
        description: "The first port to try. The CLI picks the next free port automatically."
        placeholder: "8188"
        defaultValue: "8188"
    }

    StringSetting {
        settingKey: "extraArgs"
        label: "Extra comfyui flags"
        description: "Whitespace-separated flags, for example: --highvram --preview-method auto. Quoting is not supported."
        placeholder: "--highvram"
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Status refresh"
        description: "How often the plugin asks the CLI for the current process state."
        options: [
            { label: "2 seconds", value: "2000" },
            { label: "3 seconds", value: "3000" },
            { label: "5 seconds", value: "5000" },
            { label: "10 seconds", value: "10000" }
        ]
        defaultValue: "3000"
    }

    StringSetting {
        settingKey: "logLines"
        label: "Log lines"
        description: "Number of journal lines fetched when you open the log view."
        placeholder: "200"
        defaultValue: "200"
    }

    ToggleSetting {
        settingKey: "showProjectName"
        label: "Show project name"
        description: "Show the active project name next to the ComfyUI icon in the bar."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "stopOnDisable"
        label: "Stop ComfyUI when this plugin unloads"
        description: "Runs comfyui-manager stop when the plugin daemon is destroyed. This also fires when DMS itself shuts down, so it is off by default."
        defaultValue: false
    }
}
