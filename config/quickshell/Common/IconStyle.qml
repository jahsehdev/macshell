pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "IconStyle.js" as Preset

Scope {
    id: icons
    property var settings: Preset.normalize({})
    property bool owner: false
    property bool systemDark: false
    property bool loaded: false
    readonly property string mode: settings.style
    readonly property string effectiveStyle: Preset.effectiveStyle(settings, systemDark)
    readonly property bool dark: Preset.resolvedDark(settings, systemDark)
    readonly property color tintColor: Preset.tint(settings, ThemeColors.accentFor("shell"))
    readonly property color tintForeground: Preset.foreground(String(tintColor))
    readonly property color folderColor: Preset.folder(settings, ThemeColors.accentFor("shell"))
    readonly property int effectMode: ({ default: 0, dark: 1, clear: 2, tinted: 3 })[effectiveStyle]
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string nativeSignature: [mode, dark, String(folderColor)].join("|")
    property var nativeState: ({})

    function widgetStyle(type) { return Preset.widgetStyle(settings, type, systemDark); }
    function setValue(key, value) {
        if (["style", "darkAppearance", "clearAppearance", "folderColor", "tintColor"].indexOf(key) < 0) return;
        var next = Object.assign({}, settings); next[key] = value;
        settings = Preset.normalize(next);
        preference.setText(JSON.stringify(settings, null, 2));
    }
    function reset() { settings = Preset.normalize({}); preference.setText(JSON.stringify(settings, null, 2)); }
    function folderSource(name) {
        // The generated icon theme retains the folder's own emblem artwork.
        return nativeState.icons && nativeState.icons[name || "folder"]
            ? "file://" + nativeState.icons[name || "folder"] : "";
    }
    onNativeSignatureChanged: if (owner && loaded) nativeDelay.restart()
    onOwnerChanged: if (owner && loaded) nativeDelay.restart()
    FileView {
        id: preference
        path: icons.configHome + "/macshell/icon-style.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!saved || typeof saved !== "object" || Array.isArray(saved)) return;
                icons.settings = Preset.normalize(saved);
            } catch (e) { }
            icons.loaded = true;
            if (icons.owner) nativeDelay.restart();
        }
        onLoadFailed: { icons.loaded = true; if (icons.owner) nativeDelay.restart(); }
    }
    FileView {
        path: icons.configHome + "/macshell/folders/native-state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { icons.nativeState = JSON.parse(text()); } catch (e) { } }
    }
    Timer {
        id: nativeDelay
        interval: 240
        onTriggered: { if (!nativeSync.running) nativeSync.running = true; else restart(); }
    }
    Process {
        id: nativeSync
        command: ["python3", icons.configHome + "/quickshell/Common/sync_icon_style.py",
                  "--folder-color", String(icons.folderColor), "--style", icons.mode,
                  "--dark", icons.dark ? "1" : "0"]
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("[icon-style]", text.trim()) }
    }
}
