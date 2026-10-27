pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: menu
    property string mode: "launchpad"
    readonly property bool spotlight: mode === "spotlight"
    readonly property string label: spotlight ? "Apps" : "Launchpad"
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"

    function setMode(value) {
        if (value !== "spotlight" && value !== "launchpad") return;
        mode = value;
        store.setText(JSON.stringify({ mode: mode }, null, 2));
    }

    function toggle() {
        if (spotlight)
            Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "spotlight", "apps"]);
        else
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/launchpad-toggle", "--launchpad"]);
    }

    FileView {
        id: store
        path: menu.configHome + "/macshell/app-menu.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                menu.mode = saved.mode === "spotlight" ? "spotlight" : "launchpad";
            } catch (e) { }
        }
    }
}
