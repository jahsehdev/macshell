pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "GlassMaterial.js" as Preset

Scope {
    id: material
    // One blur preset for the entire shell, independent of icon tint and the
    // translucency slider. Older installations stay Clear.
    property string mode: "clear"
    readonly property bool tinted: mode === "tinted"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macshell"

    function blurRadius(clearRadius) { return Preset.blurRadius(mode, clearRadius); }

    function setMode(value) {
        if (value !== "clear" && value !== "tinted") return;
        mode = value;
        preference.setText(JSON.stringify({ mode: mode }, null, 2));
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", configDir])
    FileView {
        id: preference
        path: material.configDir + "/liquidglass.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var saved = JSON.parse(text());
                material.mode = Preset.normalize(saved.mode);
            } catch (error) { /* Keep the last valid material during partial writes. */ }
        }
        onLoadFailed: material.mode = "clear"
    }
}
