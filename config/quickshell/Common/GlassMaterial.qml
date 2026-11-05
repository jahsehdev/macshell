pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "GlassMaterial.js" as Preset

Scope {
    id: material
    // Shared continuous material. The old mode-only preference maps to the
    // two endpoints; keep that API for existing IPC callers.
    property real intensity: 0
    readonly property string mode: intensity >= 0.5 ? "tinted" : "clear"
    readonly property bool tinted: intensity >= 1
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macshell"

    function blurRadius(clearRadius) { return Preset.blurAt(intensity, clearRadius); }
    function opacity(base) { return Preset.opacityAt(intensity, base); }

    function setIntensity(value) {
        intensity = Preset.intensity(value);
        saveTimer.restart();
    }

    function setMode(value) {
        if (value !== "clear" && value !== "tinted") return;
        setIntensity(value === "tinted" ? 1 : 0);
    }

    // Apply every drag frame in memory; coalesce disk writes after movement.
    Timer {
        id: saveTimer
        interval: 160
        onTriggered: preference.setText(JSON.stringify({ mode: material.mode, intensity: material.intensity }, null, 2))
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", configDir])
    FileView {
        id: preference
        path: material.configDir + "/liquidglass.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!saveTimer.running) material.intensity = Preset.fromSaved(saved);
            } catch (error) { /* Keep the last valid material during partial writes. */ }
        }
        onLoadFailed: material.intensity = 0
    }
}
