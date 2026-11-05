pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool active: false
    property real volume: 0
    property bool connected: false
    property string error: ""
    property string backend: ""
    // Override this list to choose a backend/device, or to inject a test stream.
    property var command: ["python3", "-B", "-u", decodeURIComponent(Qt.resolvedUrl("bin/mic_level.py").toString().replace(/^file:\/\//, ""))]

    onActiveChanged: {
        volume = 0; connected = false; error = "";
    }
    Process {
        id: worker
        command: root.command
        running: root.active
        stdout: SplitParser {
            onRead: data => {
                if (!root.active) return;
                try {
                    const event = JSON.parse(data);
                    if (event.event === "level" && typeof event.volume === "number" && isFinite(event.volume)) {
                        root.volume = Math.max(0, Math.min(1, event.volume));
                        root.connected = true;
                    } else if (event.event === "status") root.backend = event.backend || "";
                    else if (event.event === "error") { root.error = event.message; root.volume = 0; root.connected = false; }
                } catch (e) { root.error = "Could not read the microphone level."; }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("[luma-mic]", data) }
        onExited: {
            root.volume = 0; root.connected = false;
            if (root.active && !root.error) root.error = "Microphone disconnected. Click the microphone to retry.";
        }
    }
    Component.onDestruction: worker.running = false
}
