import "Common" as Common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
Scope {
    id: controller
    property var hub: null
    property var stages: []
    property var revealed: []
    property var squareWindows: []
    function hasSquareCorners(title) {
        return squareWindows.some(function(w) { return w.pid === Quickshell.processId && w.title === title; });
    }
    property string error: ""
    onErrorChanged: if (error) console.warn("[desktop-controller]", error)
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    function send(message) { if (worker.running) worker.write(JSON.stringify(message) + "\n"); }
    function activate(addr) { send({action: "activate", addr: addr}); }
    function desktop(screenName, force) {
        var monitors = Hyprland.monitors.values;
        for (var i = 0; i < monitors.length; i++) {
            var m = monitors[i].lastIpcObject;
            if (m && (!screenName || m.name === screenName)) {
                send({action: "desktop", monitor: m.id, force: force === true}); return;
            }
        }
    }
    function titlebar() {
        Quickshell.execDetached(["python3", configHome + "/quickshell/MacShell/bin/titlebar_action.py"]);
    }
    Process {
        id: worker
        running: Common.DesktopPreferences.loaded
        command: ["python3", "-B", "-u", controller.configHome + "/quickshell/MacShell/bin/desktop_controller.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    var result = JSON.parse(data);
                    if (result.stages !== undefined) controller.stages = result.stages;
                    if (result.revealed !== undefined) controller.revealed = result.revealed;
                    if (result.squareWindows !== undefined) controller.squareWindows = result.squareWindows;
                    controller.error = result.error || "";
                } catch (e) { console.warn("[desktop-controller]", String(e)); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("[desktop-controller]", text.trim()) }
        onStarted: controller.send({action: "preferences", settings: Common.DesktopPreferences.settings})
        onExited: retry.restart()
    }
    Timer { id: retry; interval: 2000; onTriggered: worker.running = true }
    Connections {
        target: Common.DesktopPreferences
        function onSettingsChanged() { controller.send({action: "preferences", settings: Common.DesktopPreferences.settings}); }
    }
}
